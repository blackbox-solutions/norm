defmodule Norm.Schema do
  @moduledoc false
  # Provides the definition for schemas

  alias __MODULE__

  defstruct specs: %{}, struct: nil

  # If we're building a schema from a struct then we need to add a default spec
  # for each key that only checks for presence. This allows users to specify
  # struct types without needing to specify specs for each key
  def build(%{__struct__: name} = struct) do
    specs =
      struct
      |> Map.from_struct()

    %Schema{specs: specs, struct: name}
  end

  def build(map) when is_map(map) do
    %Schema{specs: map}
  end

  def spec(schema, key) do
    schema.specs
    |> Enum.filter(fn {name, _} -> name == key end)
    |> Enum.map(fn {_, spec} -> spec end)
    |> Enum.at(0)
  end

  defimpl Norm.Conformer.Conformable do
    alias Norm.Conformer
    alias Norm.Conformer.Conformable

    def conform(_, input, path) when not is_map(input) do
      {:error, [Conformer.error(path, input, "not a map")]}
    end

    # Conforming a struct
    def conform(%{specs: specs, struct: target}, input, path) when not is_nil(target) do
      # Ensure we're mapping the correct struct
      cond do
        Map.get(input, :__struct__) != target ->
          short_name =
            target
            |> Atom.to_string()
            |> String.replace("Elixir.", "")

          {:error, [Conformer.error(path, input, "#{short_name}")]}

        true ->
          with {:ok, conformed} <- check_specs(specs, Map.from_struct(input), path) do
            {:ok, struct(target, conformed)}
          end
      end
    end

    # conforming a map.
    def conform(%Norm.Schema{specs: specs}, input, path) do
      check_specs(specs, input, path)
    end

    defp check_specs(specs, input, path) do
      results =
        input
        |> Enum.map(&check_spec(&1, specs, path))
        |> Enum.reduce(%{ok: [], error: []}, fn {key, {result, conformed}}, acc ->
          Map.put(acc, result, acc[result] ++ [{key, conformed}])
        end)

      errors =
        results.error
        |> Enum.flat_map(fn {_, error} -> error end)

      if Enum.any?(errors) do
        {:error, errors}
      else
        {:ok, Enum.into(results.ok, %{})}
      end
    end

    defp check_spec({key, value}, specs, path) do
      case Map.get(specs, key) do
        nil ->
          {key, {:ok, value}}

        spec ->
          {key, Conformable.conform(spec, value, path ++ [key])}
      end
    end
  end

  if Code.ensure_loaded?(StreamData) do
    defimpl Norm.Generatable do
      alias Norm.Generatable

      def gen(%{struct: target, specs: specs}) do
        case Enum.reduce(specs, %{}, &to_gen/2) do
          {:error, error} ->
            {:error, error}

          generator ->
            to_streamdata(generator, target)
        end
      end

      defp to_streamdata(generator, nil) do
        {:ok, StreamData.fixed_map(generator)}
      end

      defp to_streamdata(generator, target) do
        sd =
          generator
          |> StreamData.fixed_map()
          |> StreamData.bind(fn map -> StreamData.constant(struct(target, map)) end)

        {:ok, sd}
      end

      def to_gen(_, {:error, error}), do: {:error, error}

      def to_gen({key, spec}, generator) do
        case Generatable.gen(spec) do
          {:ok, g} ->
            Map.put(generator, key, g)

          {:error, error} ->
            {:error, error}
        end
      end
    end
  end
end
