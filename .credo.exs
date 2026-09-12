%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/", "config/", "priv/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      plugins: [{ExDNA.Credo, []}],
      requires: [],
      strict: true,
      parse_timeout: 5000,
      color: true,
      # `extra` adds to Credo's own default set rather than replacing it, so a
      # check added in a future Credo release runs without being listed here.
      # Everything below is either not Credo's, off in its defaults, or
      # configured differently.
      checks: %{
        extra: [
          ## ExSlop checks (AI-generated code slop detection); not part of Credo
          {ExSlop.Check.Warning.BlanketRescue, []},
          {ExSlop.Check.Warning.RescueWithoutReraise, []},
          {ExSlop.Check.Warning.RepoAllThenFilter, []},
          {ExSlop.Check.Warning.QueryInEnumMap, []},
          {ExSlop.Check.Warning.GenserverAsKvStore, []},
          {ExSlop.Check.Warning.PathExpandPriv, []},
          {ExSlop.Check.Warning.DualKeyAccess, []},
          {ExSlop.Check.Refactor.FilterNil, []},
          {ExSlop.Check.Refactor.RejectNil, []},
          {ExSlop.Check.Refactor.ReduceAsMap, []},
          {ExSlop.Check.Refactor.MapIntoLiteral, []},
          {ExSlop.Check.Refactor.IdentityPassthrough, []},
          {ExSlop.Check.Refactor.IdentityMap, []},
          {ExSlop.Check.Refactor.TryRescueWithSafeAlternative, []},
          {ExSlop.Check.Refactor.WithIdentityElse, []},
          {ExSlop.Check.Refactor.WithIdentityDo, []},
          {ExSlop.Check.Refactor.SortThenReverse, []},
          {ExSlop.Check.Refactor.StringConcatInReduce, []},
          {ExSlop.Check.Refactor.ReduceMapPut, []},
          {ExSlop.Check.Refactor.RedundantBooleanIf, []},
          {ExSlop.Check.Refactor.FlatMapFilter, []},
          {ExSlop.Check.Readability.NarratorDoc, []},
          {ExSlop.Check.Readability.BoilerplateDocParams, []},
          {ExSlop.Check.Readability.NarratorComment, []},
          {ExSlop.Check.Refactor.RedundantEnumJoinSeparator, []},
          {ExSlop.Check.Refactor.GraphemesLength, []},
          {ExSlop.Check.Refactor.ManualStringReverse, []},
          {ExSlop.Check.Refactor.SortThenAt, []},
          {ExSlop.Check.Refactor.SortForTopK, []},
          {ExSlop.Check.Refactor.ExplicitSumReduce, []},

          ## Checks Credo ships disabled, enabled here
          {Credo.Check.Refactor.AppendSingleItem, []},
          {Credo.Check.Refactor.CaseTrivialMatches, []},
          {Credo.Check.Refactor.DoubleBooleanNegation, []},
          {Credo.Check.Refactor.MapMap, []},
          {Credo.Check.Refactor.PerceivedComplexity, []},
          {Credo.Check.Warning.ForbiddenModule, []},
          {Credo.Check.Warning.UnusedOperation, []},
          {Credo.Check.Warning.WrongTestFileExtension, []},
          {Credo.Check.Consistency.MultiAliasImportRequireUse, []},
          {Credo.Check.Consistency.UnusedVariableNames, []},
          {Credo.Check.Design.DuplicatedCode, []},
          {Credo.Check.Design.SkipTestWithoutComment, []},
          {Credo.Check.Readability.AliasAs, []},
          {Credo.Check.Readability.BlockPipe, []},
          {Credo.Check.Readability.ImplTrue, []},
          {Credo.Check.Readability.MultiAlias, []},
          {Credo.Check.Readability.NestedFunctionCalls, []},
          {Credo.Check.Readability.OneArityFunctionInPipe, []},
          {Credo.Check.Readability.OnePipePerLine, []},
          {Credo.Check.Readability.SeparateAliasRequire, []},
          {Credo.Check.Readability.SingleFunctionToBlockPipe, []},
          {Credo.Check.Readability.SinglePipe, []},
          {Credo.Check.Readability.Specs, []},
          {Credo.Check.Readability.StrictModuleLayout, []},
          {Credo.Check.Readability.WithCustomTaggedTuple, []},
          {Credo.Check.Refactor.ABCSize, []},
          {Credo.Check.Refactor.CondInsteadOfIfElse, []},
          {Credo.Check.Refactor.FilterReject, []},
          {Credo.Check.Refactor.IoPuts, []},
          {Credo.Check.Refactor.ModuleDependencies, []},
          {Credo.Check.Refactor.NegatedIsNil, []},
          {Credo.Check.Refactor.PassAsyncInTestCases, []},
          {Credo.Check.Refactor.PipeChainStart, []},
          {Credo.Check.Refactor.RejectFilter, []},
          {Credo.Check.Refactor.UtcNowTruncate, []},
          {Credo.Check.Refactor.VariableRebinding, []},
          {Credo.Check.Warning.LeakyEnvironment, []},
          {Credo.Check.Warning.MapGetUnsafePass, []},
          {Credo.Check.Warning.MixEnv, []},
          {Credo.Check.Warning.UnsafeToAtom, []},

          ## Checks whose parameters differ from the default
          {Credo.Check.Design.AliasUsage,
           [priority: :low, if_nested_deeper_than: 2, if_called_more_often_than: 0]},
          {Credo.Check.Design.TagTODO, [exit_status: 2]},
          {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]}
        ],
        disabled: [
          # Credo cannot run these on a current Elixir and asks for them to be
          # listed here: each targets a version older than this project supports.
          {Credo.Check.Readability.PreferUnquotedAtoms, []},
          {Credo.Check.Refactor.MapInto, []},
          {Credo.Check.Warning.LazyLogging, []}
        ]
      }
    }
  ]
}
