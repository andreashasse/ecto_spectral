defmodule EctoSpectral.DataCase do
  @moduledoc "Wraps each test in a sandboxed transaction against the test database."

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Ecto.Query

      alias EctoSpectral.TestRepo
    end
  end

  setup tags do
    pid = Sandbox.start_owner!(EctoSpectral.TestRepo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
    :ok
  end
end
