defmodule Norm.SelectionTest do
  use ExUnit.Case, async: true
  import Norm

  def user_schema, do: schema(%{
    name: spec(is_binary()),
    age: spec(is_integer() and (&(&1 > 0))),
    email: spec(is_binary() and (&(&1 =~ ~r/@/)))
  })

  @input %{
    name: "chris",
    age: 31,
    email: "c@keathley.io"
  }

  describe "selection/2" do
    test "can define selections of schemas" do
      assert @input == conform!(@input, selection(user_schema(), [:age]))
      assert @input == conform!(@input, selection(user_schema(), [:age, :name]))
      assert @input == conform!(@input, selection(user_schema(), [:age, :name, :email]))
      assert @input == conform!(@input, selection(schema(%{name: spec(is_binary())}), [:name]))
      assert {:error, errors} = conform(%{age: -100}, selection(user_schema(), [:age]))
      assert errors == [%{spec: "&(&1 > 0)", input: -100, path: [:age]}]
    end

    test "works with nested schemas" do
      schema = schema(%{user: user_schema()})
      selection = selection(schema, user: [:age])

      assert %{user: %{age: 31}} == conform!(%{user: %{age: 31}}, selection)
      assert {:error, errors} = conform(%{user: %{age: -100}}, selection)
      assert errors == [%{spec: "&(&1 > 0)", input: -100, path: [:user, :age]}]
      assert {:error, errors} = conform(%{user: %{name: "chris"}}, selection)
      assert errors == [%{spec: ":required", input: %{name: "chris"}, path: [:user, :age]}]
      assert {:error, errors} = conform(%{fauxuser: %{age: 31}}, selection)
      assert errors == [%{spec: ":required", input: %{fauxuser: %{age: 31}}, path: [:user]}]
    end

    test "works with nested selections"  do
      user_with_name = schema(%{user: selection(user_schema(), [:name])})
      input = %{name: "chris"}
      assert %{user: input} == conform!(%{user: input}, selection(user_with_name))

      assert_raise ArgumentError, fn ->
        user = schema(%{name: spec(is_binary()), age: spec(is_integer())})
        required_user = selection(user)
        selection(schema(%{user: required_user}), [user: [:name]])
      end
    end

    test "returns an error if a non map input is given" do
      assert {:error, errors} = conform(123, selection(user_schema()))
      assert errors == [
        %{input: 123, path: [], spec: "not a map"}
      ]
    end

    test "if no keys are selected all keys are enforced recursively" do
      assert valid?(@input, selection(user_schema()))
      refute valid?(%{}, selection(user_schema()))
      refute valid?(%{name: "chris"}, selection(user_schema()))
      refute valid?(%{name: "chris", age: 31}, selection(user_schema()))
    end

    test "errors if there are keys that aren't specified in a schema" do
      assert_raise Norm.SpecError, fn ->
        selection(schema(%{age: spec(is_integer())}), [:name])
      end

      assert_raise Norm.SpecError, fn ->
        selection(schema(%{user: schema(%{age: spec(is_integer())})}), user: [:name])
      end

      assert_raise Norm.SpecError, fn ->
        selection(schema(%{user: schema(%{age: spec(is_integer())})}), foo: [:name])
      end
    end
  end

  describe "generation" do
    test "can generate values" do
      s =
        schema(%{
          name: spec(is_binary()),
          age: spec(is_integer())
        })

      select = selection(s, [:name, :age])

      maps =
        select
        |> gen()
        |> Enum.take(10)

      for map <- maps do
        assert is_map(map)
        assert match?(%{name: _, age: _}, map)
        assert is_binary(map.name)
        assert is_integer(map.age)
      end
    end

    test "can generate subsets" do
      s =
        schema(%{
          name: spec(is_binary()),
          age: spec(is_integer())
        })

      select = selection(s, [:age])

      maps =
        select
        |> gen()
        |> Enum.take(10)

      for map <- maps do
        assert is_map(map)
        assert match?(%{age: _}, map)
        assert is_integer(map.age)
      end
    end

    test "can generate inner schemas" do
      s = schema(%{
        user: schema(%{
          name: spec(is_binary()),
          age: spec(is_integer())
        })
      })

      select = selection(s, user: [:age])

      maps =
        select
        |> gen()
        |> Enum.take(10)

      for map <- maps do
        assert is_map(map)
        assert match?(%{user: %{age: _}}, map)
        assert is_integer(map.user.age)
      end
    end
  end
end
