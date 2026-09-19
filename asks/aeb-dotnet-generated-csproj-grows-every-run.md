# aeb: the generated .csproj GROWS by one PackageReference set per run

> **STATUS: FIXED upstream (aeb `a1a5a57`) — and my diagnosis below was WRONG.**
> The csproj is innocent: it is regenerated each run and renders its source
> artifact faithfully. What accumulated was
> `dotnet_nuget_deps_including_transitive` — `dotnet.nuget_registry` (and
> `nuget_vendored`) read the existing artifact and append, and `target_dir`
> PERSISTS between runs, so each invocation re-added the node's whole
> declaration set. Measured: 80 lines holding 5 unique coords, +5 per run.
>
> The tell was a clean experiment: deleting the csproj and running ONCE
> produced 15 xunit refs, not 1 — so it was never append-per-run on the
> csproj, and the duplication had to live upstream of it.
>
> The 'leaf shape' theory below (build_project + test in one node) was
> FALSIFIED by the servirtium-vcr session, which built a node with exactly
> that shape and watched it hold steady at 9 lines across three runs. Sv is
> immune because it declares nuget deps via setters instead of a
> `.nupkg.ae` registry node, so it never calls the buggy builders.
>
> Kept rather than rewritten, because the wrong turn is the useful part: a
> plausible hypothesis that survived one measurement and died to a control.

`dotnet/SeleniumCore.Tests/.SeleniumCore.Tests.generated.csproj` is regenerated
by aeb's dotnet SDK on every invocation, and it APPENDS rather than rewrites.

## Measured

    baseline:      12 xunit refs, 77 lines
    after run 1:   13 xunit refs, 82 lines
    after run 2:   14 xunit refs, 87 lines

+1 `PackageReference` set and +5 lines per invocation, unbounded. Earlier in the
same session it was at 8; it reached 14 without anyone touching the node.

## Why it stays invisible

NuGet only WARNS — `NU1504: Duplicate 'PackageReference' items found` — and the
file is generated, gitignored and never read by a human, so nothing surfaces it.
The build still succeeds, so it reads as healthy. It is the same shape as the
rest of this repo's expensive bugs: the failure mode looks exactly like the
good outcome.

## Not the whole SDK — a shape difference

Worth stating narrowly, because "the dotnet SDK appends" is too broad a claim.
The servirtium-vcr project runs the same aeb (v0.319-2-g5fde2d5) and does NOT
grow: its three generated csprojs were byte-identical across ~4 further leaf
invocations, measured the same way.

The likely discriminator is how the leaf drives the SDK:

- here: ONE node calls `dotnet.build_project()` (setters: `target_framework`)
  AND `dotnet.test()` — and grows.
- servirtium: `dotnet.build_project()` with setters in one node, `dotnet.pack()`
  in a separate `.dist.ae` — and does not grow.
- our own `fsharp/.tests.ae` uses `build_project_existing` + `test_existing`
  with an explicit `csproj_path`, i.e. a hand-written project, so it never
  generates one at all.

So the suspicion is the generate step running twice in one node (once per
builder) against an existing file, rather than the generator being append-only
in general. Not confirmed — someone should check whether `dotnet.test()`
re-emits the csproj instead of consuming the one `build_project()` wrote.

## Suggested fix

Truncate/rewrite the generated file rather than appending, and/or have the
second builder in a node consume the first's output instead of re-emitting.
A cheap guard: assert the generated csproj contains each PackageReference
exactly once.
