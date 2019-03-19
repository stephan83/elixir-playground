defmodule Services.ServiceTest do
  use ExUnit.Case

  alias Services.Service
  alias Services.ServiceTest.{LaidbackService, NeedyService}

  defmodule LaidbackService do
    use Service

    def start_link, do: spawn(fn -> nil end)
  end

  defmodule NeedyService do
    use Service

    def start_link, do: spawn(fn -> nil end)
    def needs, do: [LaidbackService]
  end

  describe "needs" do
    test "has a default implementation" do
      assert LaidbackService.needs() == []
    end

    test "can be overriden" do
      assert NeedyService.needs() == [LaidbackService]
    end
  end
end
