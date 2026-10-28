<!-- BEGIN KATA (managed by `kata init --with-agents`) -->
Kata is the system of record for intent.

- Never `kata delete` or `kata purge` without explicit user authorization.

~~~dot
digraph kata {
  rankdir=TB; node [shape=box];

  arrive   [shape=diamond label="Work arrives"];
  search   [label="Search first:\nkata search \"<terms>\" --agent\nReuse an open issue, else create one.\nIf create refuses a look-alike, reuse it;\n--force-new only if the work truly differs.\nNo bound workspace: refs are <project>#<id>,\nor pass --project <project>."];
  route    [shape=diamond label="Work it, or delegate it?"];

  subgraph cluster_work {
    label="";
    claim  [label="Claim and mark it tracked:\nkata claim <ref>\nkata meta set <ref> work.attention ok"];
    branch [label="If the work happens on a dedicated branch, stamp it once:\nkata meta set <ref> work.branch <branch>\nor bind at creation:\nkata create ... --meta work.branch=<branch> --idempotency-key <key>"];
    live   [label="Keep state current:\nkata meta set <ref> work.attention stuck|needs-human|ok\nkata meta set <ref> work.attention_msg \"<why>\"\nstuck = blocked; needs-human = input/review; ok = unblocked.\nRecord progress:\nkata comment <ref> -m \"<what changed>\"\nRequest attention:\nkata notify <ref> --to <actor>[/<teammate>] --message <reason>"];
    claim -> branch -> live;
  }

  subgraph cluster_delegate {
    label="";
    fanout [label="Tracked children: --parent <ref>, --meta work.branch=<branch>,\n--idempotency-key <key>, --json; capture .issue.short_id.\nSubagents: distinct KATA_TEAMMATE and\nKATA_INBOX_USER=<actor>/<teammate>; keep the actor.\nRead requests: kata inbox --for <actor>[/<teammate>].\nAfter handling: kata notify <ref> --to <actor>[/<teammate>] --clear."];
    join   [label="Join with kata wait <refs> --until attention --any\nMatches needs-human or stuck; a close also completes the wait,\nand the reported reason distinguishes which. Use --timeout so a\nwrapper can tell timeout from satisfaction."];
    coord  [label="Read delegated work.*; never write it."];
    fanout -> join -> coord;
  }

  done     [shape=diamond label="Verified complete?"];
  close    [label="kata close <ref> --done --message \"<scope and verification, 40+ chars>\"\n--evidence commit:<sha> | pr:<url> | test:<cmd> | reviewed-paths:<path>\n(or --commit, --pr, --test, --reviewed)"];
  retire   [label="kata close <ref> --message \"<why>\"\n--duplicate-of <ref> | --superseded-by <ref> (20+ chars)\n| --wontfix (60+ chars)"];
  review   [label="kata label add <ref> needs-review --comment \"<what remains>\""];
  park     [shape=diamond label="Park it?"];
  schedule [label="kata schedule <ref> <date-or-time>\nsets scheduled_on; clear with -"];
  someday  [label="kata meta set <ref> someday true --json-value\nclear with kata meta unset <ref> someday"];

  arrive -> search -> route;
  route -> claim   [label="work it"];
  route -> fanout  [label="delegate it"];
  route -> park    [label="record only"];
  live  -> done;
  coord -> done;
  done -> close    [label="yes"];
  done -> retire   [label="duplicate, superseded or dropped"];
  done -> park     [label="no"];
  park -> schedule [label="start date known"];
  park -> someday  [label="start date unknown"];
  park -> review   [label="needs review"];
}
~~~

Inbox reads stay in the selected project. For cross-project work, use kata inbox --for <actor>[/<teammate>] --all without --project or --workspace.

Parent links group work; they do not gate readiness, but a parent cannot close with open children.
Use --blocks <dependent> / --blocked-by <prerequisite> only for real prerequisites; they gate kata ready.
Use --related <ref> for context only. kata wait observes state without requiring a dependency edge.

One writer per key: only write your own work.*. Ignore work.* on closed issues; never write it there.
Before stopping, close completed work or update both work.attention and work.attention_msg for the handoff.

Schedule/someday defer work; deadlines don’t. kata deadline <ref> <date-or-time> sets deadline_on without changing readiness.
Reached schedules and deadlines use notify.* for the current owner, or the author when unowned; clear with kata notify <ref> --to <recipient> --clear.
<!-- END KATA -->

## Shared FM-1 issues (kata)

All four FM-1 repos share one kata project, `fm-1`: fm1-site (label `site`), estampie (`estampie`), FM1Kit (`fm1kit`) and FM-SWITCH (`fm-switch`). This repo's label is `fm-switch`.

- Give every issue the label of each repo it touches: `kata create "<title>" --label fm-switch ...`. Work that spans repos gets every label it needs.
- This repo's queue: `kata ready --label fm-switch --agent`; everything: `kata list --agent`; counts per repo: `kata labels`.
- Every session acts as `drew`; this repo's session signs its work with `--teammate fm-switch` (on create and comment).
- Work for another repo goes in the same project with that repo's label. To ask its session to look: `kata notify <ref> --to drew/<label> --message "<why>"`. Check this session's requests with `kata inbox --for drew/fm-switch --agent`, and clear each after handling it with `kata notify <ref> --to drew/fm-switch --clear`.
- Contacting people or repos outside these four, committing, pushing and releasing stay Drew's call.
