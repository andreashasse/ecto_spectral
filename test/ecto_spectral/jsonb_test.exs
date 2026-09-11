defmodule EctoSpectral.JSONBTest do
  @moduledoc """
  The callbacks on their own, without a database.

  `test/ecto_spectral/postgres_test.exs` covers the same type against real
  `jsonb`; these tests pin down the behaviour Ecto relies on in between.
  """
  use ExUnit.Case, async: true

  alias EctoSpectral.JSONB
  alias EctoSpectral.LoadError
  alias EctoSpectral.Test.Settings
  alias EctoSpectral.Test.Shapes
  alias EctoSpectral.Test.Tags

  @settings JSONB.init(module: Settings, type: :t)
  @lenient JSONB.init(module: Settings, type: :t, on_load_error: :error)
  @names JSONB.init(module: Tags, type: :names)

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

    test "does not quietly replace a struct with the struct's defaults" do
      # A struct is a map with atom keys, so decoding one finds none of the
      # keys it looks for and fills every field from the defaults. Validating
      # the value as a native term first is what prevents that.
      assert {:ok, %Settings{theme: :dark, notifications: false, locale: "sv"}} =
               JSONB.cast(@dark, @settings)

      assert {:ok, %Settings{theme: :light, notifications: true, locale: nil}} =
               Spectral.decode(@dark, Settings, :t, :json, [:pre_decoded])
    end

    test "keeps Spectral's detail, which load/3 and dump/3 cannot" do
      assert {:error, opts} = JSONB.cast(%{"theme" => "mauve"}, @settings)
      assert opts[:message] =~ "theme"
      assert [%Spectral.Error{location: [:theme]}] = opts[:spectral_errors]
    end

    test "rejects a value that is neither shape" do
      assert {:error, _} = JSONB.cast("dark", @settings)
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

    test "still reports :map as the Ecto type" do
      assert JSONB.type(@names) == :map
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

  test "equal?/3 compares the decoded terms" do
    assert JSONB.equal?(@dark, @dark, @settings)
    refute JSONB.equal?(@dark, %Settings{}, @settings)
    assert JSONB.equal?(nil, nil, @settings)
  end

  test "embed_as/2 dumps, because the decoded term is not JSON on its own" do
    assert JSONB.embed_as(:json, @settings) == :dump
  end

  test "format/1 names the type behind the field" do
    assert JSONB.format(@settings) =~ "EctoSpectral.Test.Settings.t"
  end
end
