defmodule Mix.Tasks.Compile.BoundaryTest do
  use ExUnit.Case, async: false
  use Boundary.CompilerTester

  setup_all do
    Mix.shell(Mix.Shell.Process)
    Logger.disable(self())

    compile_result =
      in_lib_with_boundaries(fn lib_with_boundaries ->
        in_lib_without_boundaries(fn lib_without_boundaries ->
          TestProject.in_project(
            [
              mix_opts: [
                deps: [
                  {lib_with_boundaries.app, path: "#{Path.absname(lib_with_boundaries.path)}"},
                  {lib_without_boundaries.app, path: "#{Path.absname(lib_without_boundaries.path)}"}
                ]
              ]
            ],
            &compile_project/1
          )
        end)
      end)

    {:ok, compile_result}
  end

  test "works with an empty project" do
    TestProject.in_project(fn _project -> assert TestProject.compile().warnings == [] end)
  end

  module1 = unique_module_name()

  module_test "in-boundary calls are allowed",
              """
              defmodule #{module1} do
                use Boundary

                defmodule Foo do def fun(), do: Foo.fun() end
                defmodule Bar do def fun(), do: Bar.fun() end
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "top-level dependency module is exported by default",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module2}]
                def fun(), do: #{module2}.fun()
              end

              defmodule #{module2} do
                use Boundary
                def fun(), do: :ok
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "inner module can call a dependency",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module2}]
                defmodule InnerBoundary do
                  def fun(), do: #{module2}.fun()
                end
              end

              defmodule #{module2} do
                use Boundary
                def fun(), do: :ok
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "calls to exported module are allowed",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module2}]
                def fun(), do: #{module2}.Exported.fun()

                defmodule InnerBoundary do def fun(), do: #{module2}.Exported.fun() end
              end

              defmodule #{module2} do
                use Boundary, exports: [Exported]
                defmodule Exported do def fun(), do: :ok end
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test ".{} syntax can be used to specify exports",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module2}]
                def fun1(), do: #{module2}.Inner.Exported1.fun()
                def fun2(), do: #{module2}.Inner.Exported2.fun()
              end

              defmodule #{module2} do
                use Boundary, exports: [Inner.{Exported1, Exported2}]

                defmodule Inner do
                  defmodule Exported1 do def fun(), do: :ok end
                  defmodule Exported2 do def fun(), do: :ok end
                end
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test ".{} syntax can be used to specify deps",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module2}.{Module1, Module2}]
                def fun1(), do: #{module2}.Module1.fun()
                def fun2(), do: #{module2}.Module2.fun()
              end

              defmodule #{module2}.Module1 do
                use Boundary
                def fun(), do: :ok
              end

              defmodule #{module2}.Module2 do
                use Boundary
                def fun(), do: :ok
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "ignored boundary can call anyone",
              """
              defmodule #{module1} do
                use Boundary, ignore?: true
                def fun1(), do: #{module2}.fun()
              end

              defmodule #{module2} do
                use Boundary
                def fun(), do: :ok
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "ignored boundary can be called by anyone",
              """
              defmodule #{module1} do
                use Boundary
                def fun1(), do: #{module2}.fun()
              end

              defmodule #{module2} do
                use Boundary, ignore?: true
                def fun(), do: :ok
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "call to an unclassified module is not reported",
              """
              defmodule #{module1} do
                use Boundary, externals_mode: :strict
                def fun1(), do: #{module2}.fun()
              end

              defmodule #{module2} do
                def fun(), do: :ok
              end
              """ do
    assert [%{message: "#{unquote(module2)} is not included in any boundary"}] = warnings
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "protocol implementation is by default ignored",
              """
              defmodule #{module1} do
                use Boundary
                defprotocol SomeProtocol do def foo(bar) end
              end

              defmodule #{module2} do
                use Boundary
                def fun(), do: :ok
              end

              defimpl #{module1}.SomeProtocol, for: Any do def foo(), do: #{module2}.fun() end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "protocol implementation can be classified",
              """
              defmodule #{module1} do
                use Boundary
                defprotocol SomeProtocol do def foo(bar) end
              end

              defmodule #{module2} do
                use Boundary
                def fun(), do: :ok
              end

              defimpl #{module1}.SomeProtocol, for: Any do
                use Boundary, classify_to: #{module2}
                def foo(), do: #{module1}.fun()
              end
              """ do
    assert [warning] = warnings

    assert warning.message =~ """
           forbidden call to #{unquote(module1)}.fun/0
             (calls from #{unquote(module2)} to #{unquote(module1)} are not allowed)
           """
  end

  module1 = unique_module_name()

  module_test "all boundaries must be classified",
              """
              defmodule #{module1} do end
              """ do
    assert [warning] = warnings
    assert warning.message == "#{unquote(module1)} is not included in any boundary"
  end

  module1 = unique_module_name()

  module_test "dep must be a known boundary",
              """
              defmodule #{module1} do use Boundary, deps: [NoSuchBoundary] end
              """ do
    assert [%{position: 1, message: "unknown boundary NoSuchBoundary is listed as a dependency"}] = warnings
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "dep can't be an ignored boundary",
              """
              defmodule #{module1} do use Boundary, deps: [#{module2}] end
              defmodule #{module2} do use Boundary, ignore?: true end
              """ do
    assert [%{position: 1, message: "ignored boundary #{unquote(module2)} is listed as a dependency"}] = warnings
  end

  module1 = unique_module_name()
  module2 = unique_module_name()
  module3 = unique_module_name()

  module_test "dep cycles are not allowed",
              """
              defmodule #{module1} do use Boundary, deps: [#{module2}] end
              defmodule #{module2} do use Boundary, deps: [#{module3}] end
              defmodule #{module3} do use Boundary, deps: [#{module1}] end
              """,
              context do
    # we're not verifying the actual printed cycle, because the displayed order is not stable
    assert context.output =~ "dependency cycle found"
  end

  module1 = unique_module_name()

  module_test "export must be an existing module",
              """
              defmodule #{module1} do use Boundary, exports: [NoSuchModule] end
              """ do
    assert [%{message: "unknown module #{unquote(module1)}.NoSuchModule is listed as an export"}] = warnings
  end

  module1 = unique_module_name()

  module_test "export can't be from another boundary",
              """
              defmodule #{module1} do
                use Boundary, exports: [Inner.Private]
                defmodule Inner do
                  use Boundary

                  defmodule Private do end
                end
              end
              """ do
    assert [warning] = warnings

    assert warning.message ==
             "module #{unquote(module1)}.Inner.Private can't be exported because it's not a part of this boundary"
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "can't depend on an undeclared dep",
              """
              defmodule #{module1} do
                use Boundary
                def fun(), do: #{module2}.fun()
              end

              defmodule #{module2} do
                use Boundary
                def fun(), do: :ok
              end
              """ do
    assert [warning] = warnings

    assert warning.message =~ """
           forbidden call to #{unquote(module2)}.fun/0
             (calls from #{unquote(module1)} to #{unquote(module2)} are not allowed)
           """
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "can't use unexported module",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module2}]
                def fun(), do: #{module2}.Inner.fun()
              end

              defmodule #{module2} do
                use Boundary
                defmodule Inner do def fun(), do: :ok end
              end
              """ do
    assert [warning] = warnings

    assert warning.message =~ """
           forbidden call to #{unquote(module2)}.Inner.fun/0
             (module #{unquote(module2)}.Inner is not exported by its owner boundary #{unquote(module2)})
           """
  end

  module1 = unique_module_name()

  module_test "inner boundary is treated as a top-level one",
              """
              defmodule #{module1} do
                use Boundary
                def fun(), do: #{module1}.Inner.fun()

                defmodule Inner do
                  use Boundary, top_level?: true
                  def fun(), do: :ok
                end
              end
              """ do
    assert [warning] = warnings

    assert warning.message =~ """
           forbidden call to #{unquote(module1)}.Inner.fun/0
             (calls from #{unquote(module1)} to #{unquote(module1)}.Inner are not allowed)
           """
  end

  module1 = unique_module_name()

  module_test "if no dep from external is used, all calls to that external are permitted",
              """
              defmodule #{module1} do
                use Boundary, deps: []
                def fun1(), do: LibWithBoundaries.Boundary1.fun()
                def fun2(), do: LibWithoutBoundaries.Module1.fun()
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()

  module_test "calls to undeclared external deps are not allowed in strict mode",
              """
              defmodule #{module1} do
                use Boundary, deps: [], externals_mode: :strict
                def fun1(), do: LibWithBoundaries.Boundary1.fun()
                def fun2(), do: LibWithoutBoundaries.Module1.fun()
              end
              """ do
    assert [warning1, warning2] = warnings

    assert warning1.message =~
             """
             forbidden call to LibWithBoundaries.Boundary1.fun/0
               (calls from #{unquote(module1)} to LibWithBoundaries.Boundary1 are not allowed)
             """

    assert warning2.message =~
             """
             forbidden call to LibWithoutBoundaries.Module1.fun/0
               (calls from #{unquote(module1)} to LibWithoutBoundaries.Module1 are not allowed)
             """
  end

  module1 = unique_module_name()

  module_test "can depend on a boundary from an external",
              """
              defmodule #{module1} do
                use Boundary, deps: [LibWithBoundaries.Boundary1, LibWithoutBoundaries.Module1]
                def fun1(), do: LibWithBoundaries.Boundary1.fun()
                def fun2(), do: LibWithoutBoundaries.Module1.fun()
                def fun3(), do: LibWithoutBoundaries.Module1.Module2.fun()
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()

  module_test "when depending on an external boundary, calls to other boundaries from that external are not permitted",
              """
              defmodule #{module1} do
                use Boundary, deps: [LibWithBoundaries.Boundary1, LibWithoutBoundaries.Module1]
                def fun1(), do: LibWithBoundaries.Boundary2.fun()
                def fun2(), do: LibWithoutBoundaries.Module4.fun()
              end
              """ do
    assert [warning1, warning2] = warnings

    assert warning1.message =~ """
           forbidden call to LibWithBoundaries.Boundary2.fun/0
             (calls from #{unquote(module1)} to LibWithBoundaries.Boundary2 are not allowed)
           """

    assert warning2.message =~
             """
             forbidden call to LibWithoutBoundaries.Module4.fun/0
               (calls from #{unquote(module1)} to LibWithoutBoundaries.Module4 are not allowed)
             """
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "implicit boundaries are built from all deps of this project boundaries",
              """
              defmodule #{module1} do
                use Boundary, deps: [LibWithoutBoundaries.Module1]
                def fun(), do: LibWithoutBoundaries.Module1.Module2.Module3.fun()
              end

              defmodule #{module2} do
                use Boundary, deps: [LibWithoutBoundaries.Module1.Module2.Module3]
              end
              """ do
    assert [warning] = warnings

    assert warning.message =~
             """
             forbidden call to LibWithoutBoundaries.Module1.Module2.Module3.fun/0
               (calls from #{unquote(module1)} to LibWithoutBoundaries.Module1.Module2.Module3 are not allowed)
             """
  end

  module1 = unique_module_name()

  module_test "compile-time dependencies are allowed at compile time, but not at runtime",
              """
              defmodule #{module1} do
                use Boundary, deps: [{LibWithBoundaries.Boundary2, :compile}]
                require LibWithBoundaries.Boundary2

                LibWithBoundaries.Boundary2.fun()
                def fun() do
                  LibWithBoundaries.Boundary2.macro()
                  LibWithBoundaries.Boundary2.fun()
                end

                defmacro macro do
                  # this is also allowed because we're invoking the function during compilation
                  LibWithBoundaries.Boundary2.fun()
                end
              end
              """ do
    assert [warning] = warnings

    assert warning.message =~ """
           forbidden runtime call to LibWithBoundaries.Boundary2.fun/0
             (runtime calls from #{unquote(module1)} to LibWithBoundaries.Boundary2 are not allowed)
           """

    assert warning.position == 8
  end

  module1 = unique_module_name()

  module_test "reports invalid option",
              """
              defmodule #{module1} do
                use Boundary, foo: :bar
              end
              """ do
    assert [%{message: "unknown option :foo"}] = warnings
  end

  module1 = unique_module_name()

  module_test "can't use dep or export in an ignored boundary",
              """
              defmodule #{module1} do
                use Boundary, ignore?: true, exports: [Foo], deps: [LibWithBoundaries.Boundary1]

                defmodule Foo do end
                defmodule Bar do use Boundary end
              end
              """ do
    assert [
             %{message: "deps can't be provided in an ignored boundary"},
             %{message: "exports can't be provided in an ignored boundary"}
           ] = warnings
  end

  module1 = unique_module_name()

  module_test "invalid externals_mode",
              """
              defmodule #{module1} do
                use Boundary, externals_mode: :invalid
              end
              """ do
    assert [%{message: "invalid externals_mode"}] = warnings
  end

  module1 = unique_module_name()

  module_test "can't provide extra externals in strict mode",
              """
              defmodule #{module1} do
                use Boundary, externals_mode: :strict, extra_externals: [:mix]
              end
              """ do
    assert [%{message: "extra_externals can't be provided in strict mode"}] = warnings
  end

  module1 = unique_module_name()

  module_test "module is classified to its own app",
              """
              defmodule #{module1} do
                use Boundary, deps: [{Mix, :compile}]

                def fun(), do: Mix.MyTask.fun()
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "boundary can export the top-level module of its sub-boundary",
              """
              defmodule #{module1} do
                use Boundary, exports: [SubModule]
                def fun(), do: :ok

                defmodule SubModule do
                  use Boundary
                  def fun(), do: :ok
                end
              end

              defmodule #{module2} do
                use Boundary, deps: [#{module1}]
                def fun(), do: #{module1}.SubModule.fun()
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()

  module_test "boundary is allowed to invoke exports of its direct children",
              """
              defmodule #{module1} do
                use Boundary

                def fun() do
                  #{module1}.SubBoundary.fun()
                  #{module1}.SubBoundary.Foo.fun()
                end

                defmodule SubBoundary do
                  use Boundary, exports: [Foo]
                  def fun(), do: :ok

                  defmodule Foo do def fun() do :ok end end
                end
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()

  module_test "boundary is not allowed to invoke internals of its direct children",
              """
              defmodule #{module1} do
                use Boundary
                def fun() do #{module1}.SubBoundary.Foo.fun() end

                defmodule SubBoundary do
                  use Boundary
                  defmodule Foo do def fun() do :ok end end
                end
              end
              """ do
    assert [warning] = warnings
    assert warning.message =~ "module #{unquote(module1)}.SubBoundary.Foo is not exported by its owner boundary"
  end

  module1 = unique_module_name()

  module_test "boundary can't depend on itself",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module1}]
              end
              """ do
    assert [warning] = warnings
    assert warning.message =~ "#{unquote(module1)} can't be listed as a dependency"
  end

  module1 = unique_module_name()

  module_test "boundary can't depend on its child",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module1}.SubBoundary]
                defmodule SubBoundary do use Boundary end
              end
              """ do
    assert [warning] = warnings
    assert warning.message =~ "#{unquote(module1)}.SubBoundary can't be listed as a dependency"
  end

  module1 = unique_module_name()

  module_test "boundary can depend on its child if it's explicitly declared as a top-level boundary",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module1}.SubBoundary]
                defmodule SubBoundary do use Boundary, top_level?: true end
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "boundary can't depend on someone else's child",
              """
              defmodule #{module1} do
                use Boundary, deps: [#{module2}.SubBoundary]
                defmodule SubBoundary do use Boundary end
              end

              defmodule #{module2} do
                use Boundary
                defmodule SubBoundary do use Boundary end
              end
              """ do
    assert [warning] = warnings
    assert warning.message =~ "#{unquote(module2)}.SubBoundary can't be listed as a dependency"
  end

  module1 = unique_module_name()

  module_test "boundary can't depend on an external's subboundary",
              """
              defmodule #{module1} do
                use Boundary, deps: [LibWithBoundaries.Boundary1.SubBoundary]
              end
              """ do
    assert [warning] = warnings
    assert warning.message =~ "LibWithBoundaries.Boundary1.SubBoundary can't be listed as a dependency"
  end

  module1 = unique_module_name()

  module_test "boundary can depend on its sibling",
              """
              defmodule #{module1} do
                use Boundary
                defmodule SubBoundary1 do use Boundary, deps: [#{module1}.SubBoundary2] end
                defmodule SubBoundary2 do use Boundary end
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()

  module_test "boundary can depend on its parent",
              """
              defmodule #{module1} do
                use Boundary
                defmodule SubBoundary do use Boundary, deps: [#{module1}] end
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()

  module_test "boundary can depend on a dep of its parent",
              """
              defmodule #{module1} do
                use Boundary

                defmodule SubBoundary1 do use Boundary end

                defmodule SubBoundary2 do
                  use Boundary, deps: [#{module1}.SubBoundary1]
                  defmodule SubBoundary3 do use Boundary, deps: [#{module1}.SubBoundary1] end
                end
              end
              """ do
    assert warnings == []
  end

  module1 = unique_module_name()

  module_test "boundary can't depend on a sub-boundary of a sibling of its ancestor",
              """
              defmodule #{module1} do
                use Boundary

                defmodule SubBoundary1 do
                  use Boundary
                  defmodule SubBoundary2 do use Boundary end
                end

                defmodule SubBoundary3 do
                  use Boundary
                  defmodule SubBoundary4 do use Boundary, deps: [#{module1}.SubBoundary1.SubBoundary2] end
                end
              end
              """ do
    assert [warning] = warnings
    assert warning.message =~ "#{unquote(module1)}.SubBoundary1.SubBoundary2 can't be listed as a dependency"
  end

  module1 = unique_module_name()
  module2 = unique_module_name()

  module_test "exporting multiple deps",
              """
              defmodule #{module1} do
                use Boundary, exports: [{Schemas, except: [Base]}]

                defmodule Schemas.Base do def fun(), do: :ok end
                defmodule Schemas.Foo do def fun(), do: :ok end
                defmodule Schemas.Bar do def fun(), do: :ok end
              end

              defmodule #{module2} do
                use Boundary, deps: [#{module1}]

                def fun() do
                  #{module1}.Schemas.Foo.fun()
                  #{module1}.Schemas.Bar.fun()
                  #{module1}.Schemas.Base.fun()
                end
              end
              """ do
    assert [warning] = warnings

    assert warning.message =~
             "#{unquote(module1)}.Schemas.Base is not exported by its owner boundary #{unquote(module1)}"
  end

  describe "recompilation tests" do
    setup do
      Mix.shell(Mix.Shell.Process)
      Logger.disable(self())
      :ok
    end

    test "preserves surviving warnings on partial recompile" do
      module1 = unique_module_name()
      module2 = unique_module_name()
      module3 = unique_module_name()
      module4 = unique_module_name()

      TestProject.in_project(fn project ->
        File.write!(Path.join([project.path, "lib", "mod1.ex"]), "defmodule #{module1} do end")
        File.write!(Path.join([project.path, "lib", "mod2.ex"]), "defmodule #{module2} do end")
        File.write!(Path.join([project.path, "lib", "mod3.ex"]), "defmodule #{module3} do end")

        # compile to force internal caching in compiler
        TestProject.compile()

        # removing one module with warning
        File.rm_rf!(Path.join([project.path, "lib", "mod1.ex"]))

        # fixing a warning in another module
        File.write!(Path.join([project.path, "lib", "mod2.ex"]), "defmodule #{module2} do use Boundary end")

        # creating a new file
        File.write!(Path.join([project.path, "lib", "mod4.ex"]), "defmodule #{module4} do end")

        # we're checking that compiler reports remaing warning (for the file which hasn't been recompiled), as well as
        # the newly introduced warning
        assert [warning1, warning2] = TestProject.compile().warnings
        assert warning1.message == "#{module3} is not included in any boundary"
        assert warning2.message == "#{module4} is not included in any boundary"
      end)
    end

    test "correctly reports errors if referenced externals change" do
      module1 = unique_module_name()

      in_lib_with_boundaries(fn lib ->
        TestProject.in_project(
          [mix_opts: [deps: [{lib.app, path: "#{Path.absname(lib.path)}"}]]],
          fn project ->
            File.write!(
              Path.join([project.path, "lib", "mod1.ex"]),
              """
              defmodule #{module1} do
                use Boundary
                def fun(), do: LibWithBoundaries.Boundary1.Submodule.fun()
              end
              """
            )

            # doesn't report a warning because external is not listed as a dep
            assert TestProject.compile().warnings == []

            File.write!(
              Path.join([project.path, "lib", "mod1.ex"]),
              """
              defmodule #{module1} do
                use Boundary, deps: [LibWithBoundaries.Boundary1]
                def fun(), do: LibWithBoundaries.Boundary1.Submodule.fun()
              end
              """
            )

            # Reports an error on recompile. This proves that if an external is added as a dep, boundary will correctly
            # recreate the view of the world. Internally, this proves the correct inner working of the cache.
            assert [warning] = TestProject.compile().warnings

            assert warning.message =~
                     """
                     forbidden call to LibWithBoundaries.Boundary1.Submodule.fun/0
                       (module LibWithBoundaries.Boundary1.Submodule is not exported by its owner boundary LibWithBoundaries.Boundary1)
                     """
          end
        )
      end)
    end

    test "warns on unlisted externals in strict mode" do
      module1 = unique_module_name()

      TestProject.in_project(
        [mix_opts: [project_opts: [boundary: [externals_mode: :strict]]]],
        fn project ->
          File.write!(
            Path.join([project.path, "lib", "mod1.ex"]),
            """
            defmodule #{module1} do
              use Boundary
              def fun(), do: Mix.env()
            end
            """
          )

          # doesn't report a warning because external is not listed as a dep
          assert [warning] = TestProject.compile().warnings
          assert warning.message =~ "forbidden call to Mix.env/0"
        end
      )
    end
  end

  defp in_lib_with_boundaries(fun) do
    TestProject.in_project(fn project ->
      File.write!(
        Path.join([project.path, "lib", "code.ex"]),
        """
        defmodule LibWithBoundaries.Boundary1 do
          use Boundary, deps: [], exports: []
          def fun(), do: :ok

          defmodule Submodule do def fun(), do: :ok end

          defmodule SubBoundary do
            use Boundary
            def fun(), do: :ok
          end
        end

        defmodule LibWithBoundaries.Boundary2 do
          use Boundary, deps: [], exports: []
          def fun(), do: :ok
          defmacro macro(), do: :ok
        end
        """
      )

      fun.(project)
    end)
  end

  defp in_lib_without_boundaries(fun) do
    TestProject.in_project(
      [mix_opts: [deps: [], compilers: []]],
      fn project ->
        File.write!(
          Path.join([project.path, "lib", "code.ex"]),
          """
          defmodule LibWithoutBoundaries.Module1 do
            def fun(), do: :ok

            defmodule Module2 do
              def fun(), do: :ok

              defmodule Module3 do
                def fun(), do: :ok
              end
            end
          end

          defmodule LibWithoutBoundaries.Module4 do
            def fun(), do: :ok
          end

          defmodule Mix.MyTask do
            def fun(), do: :ok
          end
          """
        )

        fun.(project)
      end
    )
  end
end
