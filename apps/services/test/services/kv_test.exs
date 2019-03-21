defmodule Services.KVTest do
  use ExUnit.Case, async: true

  alias Services.KV

  setup do
    start_supervised!(KV)
    :ok
  end

  describe "put/2" do
    test "sets the value of a key" do
      KV.put(:hello, :world)
      assert KV.get(:hello) == :world
    end
  end

  describe "delete/1" do
    test "deletes a key" do
      KV.put(:hello, :world)
      KV.delete(:hello)
      assert KV.get(:hello) == nil
    end
  end
end
