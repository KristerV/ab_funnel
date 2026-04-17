defmodule AbFunnel.TestVariants do
  use AbFunnel.Variants

  def variants do
    [
      %{key: :control, label: "Control", active: true},
      %{key: :treatment, label: "Treatment", active: true},
      %{key: :old, label: "Old variant", active: false}
    ]
  end
end
