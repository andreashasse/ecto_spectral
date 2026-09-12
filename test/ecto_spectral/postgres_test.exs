defmodule EctoSpectral.PostgresTest do
  @moduledoc """
  The type against a real Postgres instance, writing and reading actual `jsonb`.

  Everything here goes through `Ecto.Repo`, so the driver does its own JSON
  serialization and the callbacks see the decoded terms they see in production.
  """
  use EctoSpectral.DataCase, async: true

  alias Ecto.Changeset
  alias EctoSpectral.LoadError
  alias EctoSpectral.Test.Account
  alias EctoSpectral.Test.Numbers
  alias EctoSpectral.Test.Settings
  alias EctoSpectral.Test.Shapes
  alias EctoSpectral.Test.Tags

  @dark %Settings{theme: :dark, notifications: false, locale: "sv"}
  @light %Settings{theme: :light, notifications: true, locale: nil}

  defp insert!(attrs \\ %{}) do
    %Account{}
    |> Account.changeset(Map.put_new(attrs, :required_settings, @light))
    |> Repo.insert!()
  end

  defp reload(account), do: Repo.get!(Account, account.id)

  defp raw(account, column) do
    %{rows: [[value]]} =
      Repo.query!("SELECT #{column} FROM accounts WHERE id = $1", [account.id])

    value
  end

  defp corrupt!(account, column) do
    Repo.query!(~s|UPDATE accounts SET #{column} = '{"theme":"mauve"}'::jsonb WHERE id = $1|, [
      account.id
    ])

    account
  end

  defp column_type(column) do
    %{rows: [[type]]} =
      Repo.query!(
        "SELECT data_type FROM information_schema.columns WHERE table_name = 'accounts' AND column_name = $1",
        [column]
      )

    type
  end

  describe "the column" do
    test "is jsonb, not text or json" do
      for column <- ~w(settings required_settings shape names tags profile) do
        assert column_type(column) == "jsonb"
      end
    end
  end

  describe "round trips" do
    test "a struct survives insert and read" do
      account = insert!(%{settings: @dark})
      assert reload(account).settings == @dark
    end

    test "the stored document is the encoded JSON, not an Elixir term" do
      account = insert!(%{settings: @dark})

      assert raw(account, "settings") == %{
               "theme" => "dark",
               "notifications" => false,
               "locale" => "sv"
             }
    end

    test "an update writes the new value" do
      account = insert!(%{settings: @dark})

      updated =
        account
        |> Changeset.change(settings: @light)
        |> Repo.update!()

      assert reload(updated).settings == @light
      assert raw(updated, "settings")["theme"] == "light"
    end

    test "a dumped value can be compared in a where clause" do
      account = insert!(%{settings: @dark})
      _other = insert!(%{settings: @light})

      found = Repo.all(from a in Account, where: a.settings == ^@dark, select: a.id)

      assert found == [account.id]
    end

    test "insert_all dumps the same way" do
      {1, nil} =
        Repo.insert_all(Account, [%{required_settings: @light, settings: @dark}])

      assert [%Account{settings: settings}] = Repo.all(Account)
      assert settings == @dark
    end

    test "update_all casts the value it is given" do
      account = insert!(%{settings: @light})

      {1, nil} =
        Repo.update_all(from(a in Account, where: a.id == ^account.id), set: [settings: @dark])

      assert reload(account).settings == @dark

      assert raw(account, "settings") == %{
               "theme" => "dark",
               "notifications" => false,
               "locale" => "sv"
             }
    end

    test "update_all reports a value that does not match the type" do
      account = insert!(%{settings: @light})

      # update_all casts its set-values, so this is the path that used to
      # write the struct's defaults without complaint.
      assert_raise Ecto.Query.CastError, ~r/cannot be cast/, fn ->
        Repo.update_all(from(a in Account, where: a.id == ^account.id),
          set: [settings: %Settings{theme: :mauve}]
        )
      end
    end

    test "get_by finds a row by the dumped document" do
      account = insert!(%{settings: @dark})

      assert Repo.get_by(Account, settings: @dark).id == account.id
    end

    test "stream loads the same values as all/1" do
      account = insert!(%{settings: @dark})

      streamed =
        Repo.transaction(fn -> Account |> Repo.stream() |> Enum.map(& &1.settings) end)

      assert {:ok, [@dark]} = streamed
      assert reload(account).settings == @dark
    end

    test "force_change writes a value equal to the stored one" do
      account = insert!(%{settings: @dark})

      changeset = account |> Changeset.change() |> Changeset.force_change(:settings, @dark)

      assert Repo.update!(changeset).settings == @dark
    end

    test "the database can query inside the document" do
      account = insert!(%{settings: @dark})

      assert %{rows: [[id]]} =
               Repo.query!("SELECT id FROM accounts WHERE settings->>'theme' = 'dark'")

      assert id == account.id
    end
  end

  describe "NULL" do
    test "a nullable column stores and loads nil" do
      account = insert!(%{settings: nil})

      assert raw(account, "settings") == nil
      assert reload(account).settings == nil
    end

    test "an omitted field is nil too" do
      assert insert!() |> reload() |> Map.fetch!(:settings) == nil
    end

    test "cast/2 accepts nil through a changeset" do
      changeset =
        Account.changeset(%Account{}, %{"settings" => nil, "required_settings" => @light})

      assert changeset.valid?
      assert Changeset.get_change(changeset, :settings) == nil
    end
  end

  describe "a NOT NULL column" do
    test "is enforced by the database when the changeset is bypassed" do
      assert_raise Postgrex.Error, ~r/not-null constraint/, fn ->
        Repo.insert!(%Account{required_settings: nil})
      end
    end

    test "is caught earlier by validate_required/3" do
      changeset = Account.changeset(%Account{}, %{})

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.errors[:required_settings]
    end

    test "round trips like any other column" do
      account = insert!(%{required_settings: @dark})
      assert reload(account).required_settings == @dark
    end
  end

  describe "a type whose top level is a list" do
    test "a list of scalars maps onto Ecto's :map cleanly" do
      account = insert!(%{names: ["alpha", "beta"]})

      assert raw(account, "names") == ["alpha", "beta"]
      assert reload(account).names == ["alpha", "beta"]
    end

    test "a list of structs round trips too" do
      tags = [%Tags.Tag{name: "x", weight: 1}, %Tags.Tag{name: "y", weight: 2}]
      account = insert!(%{tags: tags})

      assert raw(account, "tags") == [
               %{"name" => "x", "weight" => 1},
               %{"name" => "y", "weight" => 2}
             ]

      assert reload(account).tags == tags
    end

    test "an empty list is stored as an empty JSON array, not as NULL" do
      account = insert!(%{names: []})

      assert raw(account, "names") == []
      assert reload(account).names == []
    end

    test "Postgres treats it as a jsonb array" do
      account = insert!(%{names: ["alpha", "beta"]})

      assert %{rows: [["array"]]} =
               Repo.query!("SELECT jsonb_typeof(names) FROM accounts WHERE id = $1", [account.id])
    end
  end

  describe "a self-describing union" do
    test "each variant round trips through the same column" do
      for shape <- [%Shapes.Circle{radius: 1.5}, %Shapes.Square{side: 2.0}] do
        account = insert!(%{shape: shape})
        assert reload(account).shape == shape
      end
    end

    test "the discriminator is queryable in the stored document" do
      account = insert!(%{shape: %Shapes.Circle{radius: 1.5}})

      assert raw(account, "shape") == %{"kind" => "circle", "radius" => 1.5}

      assert %{rows: [[id]]} =
               Repo.query!("SELECT id FROM accounts WHERE shape->>'kind' = 'circle'")

      assert id == account.id
    end
  end

  describe "a value both readings of the type accept" do
    test "the cast value and the loaded value agree" do
      changeset =
        Account.changeset(%Account{}, %{"mode" => "dark", "required_settings" => @light})

      account = Repo.insert!(changeset)

      assert Changeset.get_change(changeset, :mode) == :dark
      assert account.mode == :dark
      assert reload(account).mode == :dark
      assert raw(account, "mode") == "dark"
    end

    test "re-submitting the loaded value is not a change" do
      account = insert!(%{mode: "dark"}) |> reload()

      changeset = Account.changeset(account, %{"mode" => "dark"})

      assert changeset.changes == %{}
    end
  end

  describe "inside an embedded schema" do
    # embed_as/2 answers :dump, because the decoded term is a struct with atom
    # keys and atom values, which is not JSON on its own.
    test "the inner field is stored as its dumped document" do
      account =
        %Account{}
        |> Changeset.change(required_settings: @light)
        |> Changeset.put_embed(:profile, %{nickname: "ada", settings: @dark})
        |> Repo.insert!()

      assert raw(account, "profile") == %{
               "nickname" => "ada",
               "settings" => %{"theme" => "dark", "notifications" => false, "locale" => "sv"}
             }

      assert reload(account).profile.settings == @dark
    end
  end

  describe "data in the column that does not match the type" do
    test "raises EctoSpectral.LoadError by default" do
      account = insert!(%{settings: @dark}) |> corrupt!("settings")

      error = assert_raise LoadError, fn -> reload(account) end
      assert error.message =~ "mauve"
      assert [%Spectral.Error{location: [:theme]}] = error.errors
    end

    test "falls back to Ecto's own ArgumentError with on_load_error: :error" do
      account = insert!(%{lenient_settings: @dark}) |> corrupt!("lenient_settings")

      error = assert_raise ArgumentError, fn -> reload(account) end
      assert error.message =~ "cannot load"
      assert error.message =~ ":lenient_settings"
    end
  end

  describe "a jsonb document that is itself null" do
    test "loads as nil, because the driver cannot distinguish it from SQL NULL" do
      account = insert!(%{settings: @dark})
      Repo.query!("UPDATE accounts SET settings = 'null'::jsonb WHERE id = $1", [account.id])

      assert %{rows: [["null", false]]} =
               Repo.query!(
                 "SELECT jsonb_typeof(settings), settings IS NULL FROM accounts WHERE id = $1",
                 [account.id]
               )

      # It never reaches Spectral, so it is not checked against the type.
      assert reload(account).settings == nil
    end

    test "writing the field replaces it with a real NULL" do
      account = insert!(%{settings: @dark})
      Repo.query!("UPDATE accounts SET settings = 'null'::jsonb WHERE id = $1", [account.id])

      # It loaded as nil, so setting nil is not a change; force the write.
      updated =
        account
        |> reload()
        |> Changeset.change()
        |> Changeset.force_change(:settings, nil)
        |> Repo.update!()

      assert %{rows: [[nil, true]]} =
               Repo.query!(
                 "SELECT jsonb_typeof(settings), settings IS NULL FROM accounts WHERE id = $1",
                 [updated.id]
               )
    end
  end

  describe "floats, which Postgres normalises through numeric" do
    test "an ordinary float round trips" do
      account = insert!(%{number: %Numbers{value: 2.5}})

      assert reload(account).number == %Numbers{value: 2.5}
    end

    test "a float in exponent notation comes back as an integer and no longer loads" do
      # Postgres stores jsonb numbers as numeric, which drops the exponent, so
      # 1.0e10 is read back as 10000000000 and stops matching float().
      account = insert!(%{number: %Numbers{value: 1.0e10}})

      assert raw(account, "number") == %{"value" => 10_000_000_000}
      assert_raise LoadError, fn -> reload(account) end
    end
  end

  describe "a field whose :type is a Spectral type reference" do
    test "round trips" do
      account = insert!(%{number: %Numbers{value: 1.5}})

      assert reload(account).number == %Numbers{value: 1.5}
    end

    test "renders in the error Ecto builds from format/1" do
      account = insert!(%{number: %Numbers{value: 1.5}})

      Repo.query!(~s|UPDATE accounts SET number = '{"value":"x"}'::jsonb WHERE id = $1|, [
        account.id
      ])

      error = assert_raise LoadError, fn -> reload(account) end
      assert error.message =~ "{:type, :t, 0}"
    end
  end

  describe "changesets" do
    test "cast/3 decodes external params into the typed value" do
      params = %{
        "settings" => %{"theme" => "dark", "notifications" => false, "locale" => "sv"},
        "required_settings" => %{"theme" => "light", "notifications" => true, "locale" => nil}
      }

      account = %Account{} |> Account.changeset(params) |> Repo.insert!()

      assert reload(account).settings == @dark
    end

    test "an invalid document keeps Spectral's message on the changeset" do
      changeset =
        Account.changeset(%Account{}, %{
          "settings" => %{"theme" => "mauve"},
          "required_settings" => @light
        })

      refute changeset.valid?
      assert {message, opts} = changeset.errors[:settings]
      assert message =~ "theme"
      assert [%Spectral.Error{}] = opts[:spectral_errors]
    end

    test "a value that cannot be dumped fails at insert, not silently" do
      assert_raise Ecto.ChangeError, fn ->
        %Account{}
        |> Changeset.change(required_settings: @light, settings: %Settings{theme: :mauve})
        |> Repo.insert!()
      end
    end
  end
end
