defmodule AbFunnel.VariantsTest do
  use ExUnit.Case

  alias AbFunnel.TestVariants

  test "all/0 returns all variants" do
    assert length(TestVariants.all()) == 3
  end

  test "keys/0 returns only active variant keys" do
    keys = TestVariants.keys()
    assert :control in keys
    assert :treatment in keys
    refute :old in keys
  end

  test "name/1 with atom key" do
    assert TestVariants.name(:control) == "Control"
    assert TestVariants.name(:treatment) == "Treatment"
  end

  test "name/1 with string key" do
    assert TestVariants.name("control") == "Control"
  end

  test "name/1 with unknown key returns string" do
    assert TestVariants.name("unknown_thing") == "unknown_thing"
  end

  test "random_key/0 returns an active key" do
    for _ <- 1..20 do
      key = TestVariants.random_key()
      assert key in [:control, :treatment]
    end
  end
end
