defmodule AbFunnel.InactiveVariants do
  @moduledoc "A misconfiguration: every variant retired, none left to assign."
  use AbFunnel.Variants

  def variants do
    [%{key: :control, label: "Control", active: false}]
  end
end
