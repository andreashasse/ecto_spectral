defmodule EctoSpectral.JSONBTest do
  @moduledoc """
  The callbacks on their own, without a database.

  `test/ecto_spectral/postgres_test.exs` covers the same type against real
  `jsonb`; these tests pin down the behaviour Ecto relies on in between.
  """
  use ExUnit.Case, async: true

  alias EctoSpectral.JSONB
  alias EctoSpectral.LoadError
  alias EctoSpectral.Test.Modes
  alias EctoSpectral.Test.Numbers
  alias EctoSpectral.Test.Partial
  alias EctoSpectral.Test.Prefs
  alias EctoSpectral.Test.Settings
  alias EctoSpectral.Test.Shapes
  alias EctoSpectral.Test.Tags

  @settings JSONB.init(module: Settings, type: :t)
  @lenient JSONB.init(module: Settings, type: :t, on_load_error: :error)
  @names JSONB.init(module: Tags, type: :names)
  @mode JSONB.init(module: Modes, type: :mode)
  @prefs JSONB.init(module: Prefs, type: :t)
  @partial JSONB.init(module: Partial, type: :t)

  @dark %Settings{theme: :dark, notifications: false, locale: "sv"}
  @dark_json %{"theme" => "dark", "notifications" => false, "locale" => "sv"}

  describe "init/1" do
    test "keeps the module and type it was given" do
      assert %{module: Settings, type: :t} = @settings
    end

    test "defaults to raising on a load failure" do
      assert %{on_load_error: :raise} = @settings
    end

    test "requires :module" do
      assert_raise ArgumentError, ~r/requires the :module option/, fn ->
        JSONB.init(type: :t)
      end
    end

    test "requires :type" do
      assert_raise ArgumentError, ~r/requires the :type option/, fn ->
        JSONB.init(module: Settings)
      end
    end

    test "rejects an unknown :on_load_error" do
      assert_raise ArgumentError, ~r/must be :raise or :error/, fn ->
        JSONB.init(module: Settings, type: :t, on_load_error: :ignore)
      end
    end

    test "rejects an unknown option rather than ignoring it" do
      # A typo in the one option whose whole job is to be an escape hatch
      # would otherwise leave the default silently in place.
      assert_raise ArgumentError, ~r/unknown option\(s\) \[:on_load_errors\]/, fn ->
        JSONB.init(module: Settings, type: :t, on_load_errors: :error)
      end
    end

    test "accepts the field options Ecto merges in" do
      params =
        JSONB.init(
          module: Settings,
          type: :t,
          field: :settings,
          schema: Account,
          default: nil,
          source: :settings_json,
          virtual: false,
          redact: true,
          load_in_query: true,
          define_field: false
        )

      assert %{field: :settings, schema: Account} = params
    end

    test "accepts a Spectral type reference, which is how a type takes parameters" do
      assert %{type: {:type, :t, 0}} = JSONB.init(module: Numbers, type: {:type, :t, 0})
    end
  end

  test "type/1 is :map, which Postgres renders as jsonb" do
    assert JSONB.type(@settings) == :map
  end

  describe "nil" do
    # Ecto.Type dispatches to parameterized types before its own nil shortcut,
    # so a NULL column reaches all three callbacks as nil. A plain Ecto.Type
    # never sees this, which is what makes it easy to get wrong.
    test "cast/2 passes nil through" do
      assert JSONB.cast(nil, @settings) == {:ok, nil}
    end

    test "load/3 passes nil through" do
      assert JSONB.load(nil, nil, @settings) == {:ok, nil}
    end

    test "dump/3 passes nil through" do
      assert JSONB.dump(nil, nil, @settings) == {:ok, nil}
    end
  end

  describe "cast/2" do
    test "decodes an external JSON document" do
      assert JSONB.cast(@dark_json, @settings) == {:ok, @dark}
    end

    test "passes an already-valid term through unchanged" do
      assert JSONB.cast(@dark, @settings) == {:ok, @dark}
    end

    test "reports an invalid struct instead of falling back to the defaults" do
      # The dangerous case: the value is the right shape but the wrong
      # contents, so encoding returns an error rather than raising. Reading it
      # as a document would succeed, with every field replaced by a default.
      invalid = %Settings{theme: :mauve, notifications: false, locale: "sv"}

      assert {:ok, %Settings{theme: :light, locale: nil}} =
               Spectral.decode(invalid, Settings, :t, :json, [:pre_decoded])

      assert {:error, opts} = JSONB.cast(invalid, @settings)
      assert [%Spectral.Error{location: [:theme]}] = opts[:spectral_errors]
    end

    test "a map with atom keys is a term of the type, not a document" do
      # The same hazard without a struct in sight. Reading this as a document
      # matches none of its keys, so it would cast to the type's defaults and
      # overwrite whatever the row already held.
      assert JSONB.cast(%{theme: :dark, rows: 10}, @prefs) == {:ok, %{theme: :dark, rows: 10}}

      assert {:ok, %{}} =
               Spectral.decode(%{theme: :dark, rows: 10}, Prefs, :t, :json, [:pre_decoded])
    end

    test "reports an invalid map with atom keys" do
      assert {:error, opts} = JSONB.cast(%{theme: :mauve, rows: 10}, @prefs)
      assert [%Spectral.Error{}] = opts[:spectral_errors]
    end

    test "still decodes the document form of the same type" do
      assert JSONB.cast(%{"theme" => "dark", "rows" => 10}, @prefs) ==
               {:ok, %{theme: :dark, rows: 10}}
    end

    test "an atom key nested inside a document makes it a term, not a document" do
      assert {:error, _opts} = JSONB.cast(%{"theme" => %{nested: true}}, @settings)
    end

    test "keeps fields a type does not expose" do
      # `only` drops them on the way to the column, which is what the type
      # asks for. Dropping them here too would lose data the caller still
      # holds.
      value = %Partial{name: "a", age: 30, secret: "s"}

      assert JSONB.cast(value, @partial) == {:ok, value}
      assert JSONB.dump(value, nil, @partial) == {:ok, %{"name" => "a"}}
    end

    test "answers with the term load/3 would return for the same value" do
      # "dark" is a valid String.t() and also the encoding of :dark, so both
      # readings of it succeed and disagree. Keeping the string here would
      # make the same row read back differently after a reload.
      assert JSONB.cast("dark", @mode) == {:ok, :dark}
      assert JSONB.load("dark", nil, @mode) == {:ok, :dark}
      assert JSONB.cast(:dark, @mode) == {:ok, :dark}
    end

    test "leaves a value alone when only one reading claims it" do
      assert JSONB.cast("other", @mode) == {:ok, "other"}
      assert JSONB.load("other", nil, @mode) == {:ok, "other"}
    end

    test "is no stricter than the type: an unmatched document casts to defaults" do
      # Spectral ignores keys the type does not mention and fills omitted
      # fields from the struct defaults, so a misspelled form field is not an
      # error here. Ecto.Changeset validations are the place for that.
      assert JSONB.cast(%{"them" => "dark"}, @settings) == {:ok, %Settings{}}
      assert JSONB.cast(%{}, @settings) == {:ok, %Settings{}}
    end

    test "keeps Spectral's detail, which load/3 and dump/3 cannot" do
      assert {:error, opts} = JSONB.cast(%{"theme" => "mauve"}, @settings)
      assert opts[:message] =~ "theme"
      assert [%Spectral.Error{location: [:theme]}] = opts[:spectral_errors]
    end

    test "rejects a value that is neither shape" do
      assert {:error, _opts} = JSONB.cast("dark", @settings)
    end

    test "reports the decoding error when a document is almost right" do
      assert {:error, opts} =
               JSONB.cast(%{"theme" => "dark", "notifications" => "yes"}, @settings)

      assert [%Spectral.Error{location: [:notifications]}] = opts[:spectral_errors]
    end
  end

  describe "dump/3" do
    test "produces the map the driver will encode" do
      assert JSONB.dump(@dark, nil, @settings) == {:ok, @dark_json}
    end

    test "loses the reason, because the callback has nowhere to put it" do
      assert JSONB.dump(%Settings{theme: :mauve}, nil, @settings) == :error
    end
  end

  describe "load/3" do
    test "decodes the map the driver already decoded" do
      assert JSONB.load(@dark_json, nil, @settings) == {:ok, @dark}
    end

    test "raises by default, since bad stored data is a bug not user input" do
      error =
        assert_raise LoadError, fn -> JSONB.load(%{"theme" => "mauve"}, nil, @settings) end

      assert error.message =~ "EctoSpectral.Test.Settings.t"
      assert [%Spectral.Error{location: [:theme]}] = error.errors
    end

    test "is no stricter than the type: an unrelated document loads as defaults" do
      # load/3 catches a key that is present and wrong, not a document that
      # has nothing to do with the type.
      assert JSONB.load(%{"totally" => "unrelated"}, nil, @settings) == {:ok, %Settings{}}
      assert JSONB.load(%{}, nil, @settings) == {:ok, %Settings{}}
    end

    test "bounds the size of the message, however deep the document nests" do
      deep =
        Enum.reduce(1..18, %{"x" => 1}, fn _i, acc -> %{"a" => acc, "b" => acc, "c" => acc} end)

      error =
        assert_raise LoadError, fn ->
          JSONB.load(%{"theme" => deep, "notifications" => true, "locale" => nil}, nil, @settings)
        end

      assert byte_size(error.message) < 1024
    end

    test "falls back to Ecto's :error with on_load_error: :error" do
      assert JSONB.load(%{"theme" => "mauve"}, nil, @lenient) == :error
    end

    test "names the field and schema when Ecto supplied them" do
      params = JSONB.init(module: Settings, type: :t, field: :settings, schema: Account)

      error = assert_raise LoadError, fn -> JSONB.load(%{"theme" => "mauve"}, nil, params) end
      assert error.message =~ ":settings"
      assert error.message =~ "Account"
    end
  end

  describe "a type whose top level is a list" do
    test "casts, dumps and loads without a separate field type" do
      assert JSONB.cast(["a", "b"], @names) == {:ok, ["a", "b"]}
      assert JSONB.dump(["a", "b"], nil, @names) == {:ok, ["a", "b"]}
      assert JSONB.load(["a", "b"], nil, @names) == {:ok, ["a", "b"]}
    end
  end

  describe "unions" do
    test "round trips each variant of a self-describing union" do
      params = JSONB.init(module: Shapes, type: :shape)

      for value <- [%Shapes.Circle{radius: 1.5}, %Shapes.Square{side: 2.0}] do
        assert {:ok, dumped} = JSONB.dump(value, nil, params)
        assert JSONB.load(dumped, nil, params) == {:ok, value}
      end
    end
  end

  describe "equal?/3" do
    test "compares the decoded terms" do
      assert JSONB.equal?(@dark, @dark, @settings)
      refute JSONB.equal?(@dark, %Settings{}, @settings)
      assert JSONB.equal?(nil, nil, @settings)
    end

    test "counts an integer and the same value as a float as a change" do
      # Ecto.Changeset drops a change that is equal?/3 to the stored value,
      # and 1 and 1.0 are different documents once they reach the column.
      params = JSONB.init(module: Numbers, type: :t)

      refute JSONB.equal?(%Numbers{value: 1}, %Numbers{value: 1.0}, params)
      assert JSONB.equal?(%Numbers{value: 1.0}, %Numbers{value: 1.0}, params)
    end
  end

  test "embed_as/2 dumps, because the decoded term is not JSON on its own" do
    assert JSONB.embed_as(:json, @settings) == :dump
  end

  describe "format/1" do
    test "names the type behind the field" do
      assert JSONB.format(@settings) =~ "EctoSpectral.Test.Settings.t"
    end

    test "survives a type reference, which Ecto renders while building errors" do
      params = JSONB.init(module: Numbers, type: {:type, :t, 0})

      assert JSONB.format(params) =~ "{:type, :t, 0}"
    end
  end

  describe "a Spectral type reference as :type" do
    @reference JSONB.init(module: Numbers, type: {:type, :t, 0})

    test "casts, dumps and loads" do
      value = %Numbers{value: 1.5}

      assert JSONB.cast(%{"value" => 1.5}, @reference) == {:ok, value}
      assert JSONB.dump(value, nil, @reference) == {:ok, %{"value" => 1.5}}
      assert JSONB.load(%{"value" => 1.5}, nil, @reference) == {:ok, value}
    end
  end

  describe "EctoSpectral.LoadError" do
    test "has a message even when raised bare" do
      error = assert_raise LoadError, fn -> raise LoadError end

      assert Exception.message(error) =~ "did not match its Spectral type"
    end
  end
end
