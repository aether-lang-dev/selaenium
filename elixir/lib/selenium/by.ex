defmodule Selenium.By do
  @moduledoc """
  Selenium-style `By` locator factory. Each function returns a `{strategy,
  value}` locator that `Selenium.find_element/2` and `Selenium.find_elements/2`
  accept, mirroring Selenium's `By.id(...)`/`By.className(...)`.

  `class_name/1` maps to the W3C "class name" strategy (NOT "className"),
  matching every other Selenium binding.
  """

  @type locator :: {atom() | String.t(), String.t()}

  @spec id(String.t()) :: locator
  def id(value), do: {:id, value}

  @spec name(String.t()) :: locator
  def name(value), do: {:name, value}

  @spec class_name(String.t()) :: locator
  def class_name(value), do: {:class_name, value}

  @spec css(String.t()) :: locator
  def css(value), do: {:css_selector, value}

  @spec css_selector(String.t()) :: locator
  def css_selector(value), do: {:css_selector, value}

  @spec tag_name(String.t()) :: locator
  def tag_name(value), do: {:tag_name, value}

  @spec link_text(String.t()) :: locator
  def link_text(value), do: {:link_text, value}

  @spec partial_link_text(String.t()) :: locator
  def partial_link_text(value), do: {:partial_link_text, value}

  @spec xpath(String.t()) :: locator
  def xpath(value), do: {:xpath, value}
end
