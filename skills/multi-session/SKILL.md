---
name: multi-session
description: Two or more Claude sessions in one repo — detection, worktree isolation, what crosses the boundary anyway (including a shared checkout, where an uncommitted edit already reaches their build, and the shared auto-memory directory), verifying the union of both diffs, merging the files both sides touch, handover, and teardown — including the ~5 GB of DerivedData and the LaunchServices registrations that removing the worktree leaves behind. Load when `git status` shows changes you did not make, or `ListAgents` lists a live peer on the same project.
---

# Two sessions, one repo

Written 18.8.2026 after a day of it: one session on one feature in the shared checkout, one on another
in a worktree. Both shipped, and the merge cost nothing — but only because of the checks below.
Every rule is something that day cost or nearly cost.

Extended 19.8.2026 by the **other** arrangement: both sessions in the **same** checkout, all day,
neither in a worktree. Nothing was lost there either, but three of that day's rules were caught by
the peer rather than by me — including one in a section I had open at the time. The additions are
marked where they land; they cluster in §1, §3, §5 and §7.

Companion to `agent-delegation` (an agent you spawned, whose worktree you control) — this file is
about a **peer you do not control** and cannot interrupt.

---

## 1. Detection — you find out by looking, never by being told

`git status` showing files you did not touch is the whole signal. Nothing announces it.

    git status --short          # changes you did not make?
    git branch --show-current   # are you even where you think you are?
    git worktree list           # who else has a checkout, and on what
    ListAgents                  # is the peer live right now

⚠️ **Do this before the first write, not before the first commit.** By commit time you have already
edited files they may be holding, and the cheap move (take a worktree) has become an expensive one
(move work between trees).

🔴 **`git worktree list` is not optional, because the peer may be in YOUR checkout.** This file was
written for one-in-checkout / one-in-worktree, and on 19.8.2026 both sessions were in the **same**
checkout the whole day. That case behaves differently in three places — §3 (your unsaved edits
cross), §5 (their build already consumed your file) and §7 (they need no rebase) — so establish
which one you are in before writing a single line of handover.

⚠️ **A clean `git status` at the start proves nothing about the next hour.** On 19.8.2026 it was
clean when the session began and the peer's files appeared in it mid-task, with no signal of any
kind. Re-check before you stage, not only before you start.

## 2. Isolation — your own worktree, and the two ways EnterWorktree misfires

**The session already in the shared checkout does not move.** Whoever arrives second takes the
worktree. Take it even for a small change: the cost is one command, and the alternative is finding
the collision inside a `git add`.

    EnterWorktree({name: "<short-task-name>"})

Two failures, both observed on 18.8.2026:

- **It creates the worktree in whatever repo the session cwd is in.** An earlier `cd ~/.claude` in
  the same session sent it there, where it died on a git-crypt smudge filter. **`cd` to the project
  root as its own command first**, then call the tool.
- **The base ref is `origin/<default-branch>`, not your local HEAD** (`worktree.baseRef: fresh`).
  Work you have not pushed will not be there. Push first, or check inside the new worktree with
  `git merge-base --is-ancestor <sha> HEAD`.

Inside a worktree session the harness refuses commands it cannot prove stay inside it — compound
pipelines, redirects to the parent, `--work-tree=`. **Split into plain commands; do not route
around it.**

### 🔴 A fresh worktree has no dependencies, and the first red suite will look like your bug

A worktree is a checkout of tracked files. **Everything gitignored is absent** — and in a repo with
npm packages that means `node_modules`. If a pre-commit hook or a test script drives those
packages, it goes red in a brand-new worktree for a reason that has nothing to do with your change,
and **the failure is indistinguishable from a real one**. It cost a session three rounds on
28.8.2026 before they stopped debugging their own diff.

**So install immediately after `EnterWorktree`, before the first commit — not when it bites.**
Do it per package: `git ls-files '*/package.json' 'package.json' | grep -v node_modules` lists what the
repo has, then `npm install --prefix <dir>` for every package a hook or a test script reaches.


⚠️ **`npm install` may rename `package-lock.json`** or otherwise touch tracked files. Check
`git status` afterwards and revert what you did not mean to change — a lockfile is a generated
artifact and §3 applies to it.

⚠️ The same class covers anything else gitignored that a gate reads: build caches, `.build`,
fetched fixtures. **Ask what the hooks run before you ask what your change broke.** Incident:
auto-memory `a-fresh-worktrees-red-is-missing-dependencies`.

## 3. What crosses the boundary anyway

Isolation is per-file, not per-repo. Six kinds collide however clean your worktree is:

| Kind | Example | Why it collides |
|---|---|---|
| **Generated artifacts** | `project.pbxproj` | both sides add file references |
| **Allowlists** | `Package.swift` `sources:` | both sides add entries |
| **Append-at-the-top docs** | `CHANGELOG.md`, `AUDIT_BACKLOG.md`, `KNOWN_BUGS.md` | both sides insert at line 3 |
| **The index itself** | | a hook that reads the whole staged set judges *their* content too |
| **Your UNSAVED-to-git edits** (shared checkout only) | any `Shared/` file | one working tree — your save is in their next build before a commit exists to notice it |
| **The auto-memory directory** | `~/.claude/.../memory/MEMORY.md` | not the repo you are thinking about, and `MEMORY.md` is a whole-file write |

**Consequence for staging:** `git add -A` is banned globally anyway; here the form is
`git commit --only <explicit paths>`, because a hook reading the index will block you over claims in
files you never touched.

🔴 **`git add <directory>` is `-A` inside that directory.** It takes untracked files someone else
wrote there. The ban is not on the `-A` flag, it is on staging by shape instead of by name, and a
directory argument is its quiet variant. *(19.8.2026: this swept four of the peer's memory files
into my commit in `~/.claude` — while I was writing up a different lesson about concurrent
sessions.)*

🔴 **`git commit --amend` throws the path discipline away.** It rebuilds the commit from the
**index**, so a peer's staged file lands inside your commit, under your message, with no warning of
any kind. `--only` on the original commit does not protect the amend. **The only tell is the
changed-file count amend prints** — read it every time, and run `git diff --cached --name-only`
before any amend and expect it empty.
Recovery is unstaging, not history
surgery: `git restore --source=HEAD^ --staged <path>` then amend again — then tell them, because
their work is uncommitted again and they believe it is safe.

⚠️ **A `--only` commit builds a temporary index from your paths alone**, so a pre-commit hook that
judges "the staged set" never sees their files. A green hook there is a statement about your paths,
not about the tree.

⚠️ **`~/.claude` is a second shared repo, and nothing about the project reminds you of it.** Both
sessions write auto-memory into the same directory. Two specifics:

- **`MEMORY.md` is rewritten whole**, so simultaneous writes end last-writer-wins — **silently, with
  no conflict and no git to notice**. Read it fresh immediately before writing, then `grep` your own
  line back afterwards. ⚠️ **A botched write destroys THEIR uncommitted lines and `git restore`
  cannot bring those back** — it restores HEAD, which never had them. *(20.8.2026:
  `open(p,"w").write(open(p).read()...)` truncates at argument-evaluation time; `MEMORY.md` went to
  0 bytes and the peer's two index lines were gone for good. Tell them immediately — they cannot
  detect it, because they read their lines back after writing and the lines were there then.)*
- **Its files are stored binary** (git-crypt: `git check-attr -a` shows `filter: git-crypt`), so
  `git log -S` over content returns nothing and `--stat` shows `0 insertions(+), 0 deletions(-)`.
  The commit message is the only index into that history — which is also why a message describing
  one lesson while carrying five is worse there than in an ordinary repo.

**Before writing a memory file, check whether the peer already wrote the same lesson.** Two sessions
on one incident produce two files. Resolve it by **topic, not by who found it** — the better-named,
more findable file wins and the other shrinks to a `[[pointer]]`. Trim only your own; deleting
theirs is not yours to do.

## 4. Merging — merge THEIR work into YOURS, then fast-forward

Never the other way round. Conflicts get resolved where you can verify them, and the shared branch
only ever moves by fast-forward.

    git fetch origin
    git merge main --no-commit --no-ff      # in YOUR worktree

**Generated artifact — regenerate, do not merge.** Take one side whole, re-run the generator, then
verify **both** sides survived:

    git checkout --theirs <path/to/project.pbxproj>
    ruby <the-add-files-script>.rb          # idempotent by construction
    # then assert target membership for THEIR files too, not only yours

⚠️ When querying membership with the `xcodeproj` gem, compare `File.basename(file_ref.path)` — for
`Shared/` files the stored path is the full relative path, so a basename comparison returns empty and
reads exactly like "this file is in no target".

**Append-at-the-top docs — concatenation, not a choice.** Both sides only insert; keep both, and
**check conservation explicitly**: both sections and the entire tail must appear in the result
verbatim. This is the one place where "each side deleted a different neighbouring row" happens
without anyone noticing.

🔴 **But check the premise first: "both sides only inserted" is a CLAIM, and it fails the moment
you have REWRITTEN a section on your own branch.** Then the other parent still carries your old
text, and concatenating the two conflict halves resurrects it — you get the new heading, their
section, and your pre-rewrite copy further down, all three green to git.
*(2.9.2026: two CHANGELOG conflicts three hours apart. The first really was insert-vs-insert and
concatenation was right. For the second I reused the same script, and it produced a file carrying
both the rewritten section and the stale one 57 lines below it.)*

The tell is in the conservation check, so **run it and believe it**: it reported "theirs: 14 lines
lost", and those 14 were exactly the lines my own later commit had rewritten. Resolve that case by
building the result from **your HEAD** — which already holds the rewrite — and inserting only the
other side's NEW section into it. Then assert what actually matters: every line of HEAD survives,
every line of their new section survives, the pre-rewrite heading appears **zero** times, and each
new heading exactly once.

**Allowlists — keep both entries.** And remember an allowlist is not an exclude list: a file missing
from it is invisible to the test target with no error at all.

## 5. Verification — of the merged tree, not of your branch

Your branch was green against a base that no longer exists; so was theirs. Before moving any shared
ref:

- the **full** test suite on the merged tree (not `--filter`)
- a build of **every platform the union of both changes touches**
- for generated artifacts, a per-file assertion — from **both** sides — that it compiled in the
  targets it belongs to

🔴 **"Which platforms does MY diff touch" is the wrong question, and it is the one you will ask.**
It is the union of both diffs, and you cannot answer it from your own `git diff` — you have to read
theirs. On 19.8.2026 I had this file open, this section included, and still built only the two
platforms my own change touched. **The peer caught it, not me.** Having the rule loaded is not the
same as applying it; make the union an explicit step, not a judgement.

⚠️ **In a shared checkout their build may already have compiled your change, so yours reports
`UP-TO-DATE` with zero compiles** — a green marker over an empty build. Same day: their four-platform
run consumed my `Shared/` edit minutes before I committed it, and my later run had nothing left to
do on macOS and tvOS. Read as `SUCCEEDED=1 FAILED=0` that looks like coverage. **After a peer has
built, `--force --file` is mandatory**, with a file that platform genuinely carries — verify the
target's Sources phase, or you have only warmed a random file.

⚠️ **A test suite that fails while the peer is writing is not your regression.** Three failures and
four passes inside one twenty-minute window, from reading their files mid-write. **Do not bisect
your own change against it:** stash-and-compare is confounded, because stashing removes only YOUR
half while they keep editing. What settles it is re-running after their commit lands, plus asking
whether the suite can even reach your changed files.

The measurements behind these three, written by the two sessions that hit them, live in auto-memory
— this file carries the rule, those carry the incident, and **on any conflict this file wins**
(it is the maintained copy, and it is not git-crypt, so it is greppable).

**A merge commit trips claim-checking hooks with the other session's prose**, because the staged
diff is their whole body of work. Verify before writing `[claims-ok]`:
`git grep -F "<flagged sentence>" main` must find it. Then say in the message that it is theirs and
already committed — an unexplained `[claims-ok]` on a merge is indistinguishable from a bypass.

## 6. Moving the shared branch — do not touch their checkout

    git push origin HEAD:main

Their working tree, index and local branch ref stay untouched; they pull when they choose. **Do not
try to fast-forward the local ref** — git refuses while the branch is checked out in another
worktree, and that refusal is protecting both of you.

## 7. Handover — SendMessage, and what it must contain

    ListAgents                          # find the live peer
    SendMessage({to: "<name>", ...})

### Message economy — this is a rule, not a style preference

🔴 **Two messages per topic. Not six.** One to hand over, one to confirm. The operator's instruction,
20.8.2026, after a single coordination — one label fix — cost eight messages between two sessions.
Every one of them was individually reasonable and the total was waste.

- **Do not invite elaboration.** No "let me know what you think", no offering options the other
  session did not ask for, no "tell me if you want me to also…". An open question costs a round
  trip; decide it yourself and say what you decided, so a reply is only needed to *object*.
- **Say the decision, not the deliberation.** "Merged your two points into my file, yours is
  untracked, delete it when you like" ends the topic. "Which of us should keep it?" does not.
- **Do not thank, do not apologise at length, do not restate what they just told you.** One line
  acknowledging a correction is enough; the fix is the acknowledgement.
- **Bundle.** If three things happened, they go in one message, not three.
- **Close the topic explicitly** — "nothing further from me on this" — so silence reads as done
  rather than as pending.

### 🔴 A ref you report to a peer must come from `ls-remote`, not from push or pull

On 2.9.2026 two sessions reached **opposite wrong answers** about whether one commit was on origin,
within two minutes, and neither git command lied:

| what was read | what it actually answers |
|---|---|
| `git push -q && echo "pushed"` | the command did not fail — **no read of the remote ref at all** |
| `git pull --ff-only` → *Already up to date* | your branch vs your **remote-tracking ref**, a local file |
| `git status` → *up to date with origin/main* | the same local file |
| **`git ls-remote --heads origin`** | **where the server's ref points, right now** |

`ls-remote` returned the commit for `refs/heads/main`; it had been on origin the whole time
*(measured 2.9.2026 17:14:54Z, commit stamped 17:12:28Z)*.

⚠️ **A shared checkout makes the vacuous answer GUARANTEED true, which is what makes it dangerous.**
When both sessions commit into one working copy — `~/.claude` is exactly this — your peer's commit is
already in local history before they fetch anything, so their *Already up to date* is **correct** and
carries zero information about origin. A correct answer is far more convincing than a wrong one.
Compare SHAs before you write "pushed" in a message someone else will act on.

The exceptions where a message is worth it regardless: their work is at risk, you damaged
something of theirs, or they are about to act on something you know is stale.

**You cannot verify which session you reached.** Open with who you are and which project, and add
"if you are not that session, ignore this".

A handover that says only "I pushed" is useless. It must carry:

1. **New head SHA and the previous one**, so they can see the gap.
2. **What did NOT move** — their checkout, their uncommitted work, their branch ref. Say it was
   *verified* (`git worktree list`), not assumed: that is the thing they are actually worried about.
3. **What they must do** — and this depends on where they are, so answer §1 first:
   - peer in **their own worktree** → `git fetch && git rebase origin/main` before their next commit;
   - peer in **the same checkout as you** → **nothing**. Their HEAD moved with yours; telling them to
     rebase is an instruction written for a situation they are not in, and it advertises that you did
     not check. *(19.8.2026: I sent exactly that; they replied with `git worktree list` showing one
     entry.)*
   - 🔴 peer whose branch **another branch is built on** → **do not tell them to rebase at all.**
     Rebasing rewrites the commits the descendant is based on, and if anything is working on that
     descendant right now you have just moved the ground under it. They should merge `origin/main`
     INTO theirs instead and verify the union — the other half of §4, applied in their tree rather
     than yours. *(28.8.2026: I sent "rebase before your next commit" to a peer on `e2e-harness`;
     `<a feature branch>` descended from it with two commits and a live agent on top. They declined
     and were right. Verified afterwards: `git merge-base --is-ancestor e2e-harness <a feature branch>`
     → true.)*

     ⚠️ **`git worktree list` cannot tell you this** — it shows which branch each tree is on, never
     which branch is built on which. Ask git directly before writing the instruction:

         git for-each-ref --format='%(refname:short)' refs/heads | while read b; do
           git merge-base --is-ancestor "<their-branch>" "$b" && echo "$b descends from theirs"
         done

     And the general form, because the enumeration above will grow again: **the "what they must do"
     line is a claim about a topology you have not measured.** Either measure it, or say what moved
     and let them choose — they know their own tree and you do not.
4. **The file list where you overlap.**
5. **Your conflict recipes, per file.** You already solved them; making them solve them again is how
   two resolutions diverge.
6. **Traps you personally hit**, including the ones that cost you time.
7. **Anything you wrote into a shared dashboard**, so they do not re-report it as a new finding.
8. **Anything you wrote into shared auto-memory**, for the same reason and one more: they may be
   writing the same lesson right now, and two files on one incident is the usual outcome (§3).

⚠️ **Ask for their result even when it is green.** "I'll tell you if it goes red" makes silence
indistinguishable from success, from a run that died, and from one nobody started — and you will
then report a green you never saw. Say so explicitly when handing off anything they will verify.

## 8. Teardown — and the warning that lies

Before removing anything, five checks:

    git status --short                                   # clean?
    git status --porcelain --untracked-files=all         # really clean?
    git stash list                                       # nothing parked?
    git merge-base --is-ancestor HEAD origin/main        # everything landed?
    git ls-remote --heads origin <branch>                # branch survives remotely?

Only with all five: `ExitWorktree({action: "remove", discard_changes: true})`.

⚠️ **"Discarding N commits" is measured against the LOCAL branch ref.** On 18.8.2026 it claimed 8
commits would be lost that were already on `origin/main` — the local `main` was simply behind. The
five checks are what turns `discard_changes: true` into an informed decision instead of a gamble.

**Then verify the shared checkout did not follow you:**

    git worktree list        # shared checkout still on ITS branch — compare by SHA
    git branch --show-current

A pruned worktree has moved the shared checkout onto its branch before. Compare SHAs, not names.

### Sweeping empty worktrees

    git worktree prune                                            # stale registrations
    git worktree list --porcelain | awk '/^branch /{print $2}'    # what is left

For each remaining branch, `git log --oneline origin/main..<branch>` — empty output means the
worktree holds nothing unique and can go. ⚠️ **A non-empty result is not automatically live work**:
check whether those commits are an abandoned experiment before keeping the directory forever. And a
worktree whose branch is fully merged still holds value if its working tree is dirty — check that
first, which is what the five checks above are for.

### 🔴 Removing the worktree does NOT remove what it built — ~5 GB stays behind

`ExitWorktree` and `git worktree prune` take the checkout. They know nothing about **DerivedData**,
and each worktree that ever built has its own directory of about **5 GB** that nothing ever
collects (measured 30.8.2026: four of them held 19.6 GB while the volume was at 97 %).

**Do this as the last step of teardown, while you still know which worktree was yours.**

⚠️ A project whose build scripts point DerivedData into the checkout itself leaves nothing in
`~/Library/Developer/Xcode/DerivedData` for a worktree built only through them — the sweep below is for
worktrees built by a bare `xcodebuild` or by the Xcode GUI, and for older leftovers.


🔴 **Identify by `WorkspacePath`, never by date or by size.** A removed worktree leaves a
FRESHLY-dated directory, and the main checkout's can be the oldest one there — so mtime points the
wrong way, and the deletion you make on it is the expensive one.

    D=~/Library/Developer/Xcode/DerivedData
    for d in $D/*-*; do
      [ -d "$d" ] || continue
      WP=$(/usr/libexec/PlistBuddy -c "Print :WorkspacePath" "$d/info.plist" 2>/dev/null)
      printf "%-52s %6s  %s\n    -> %s\n" "$(basename $d)" \
             "$(du -sh "$d" 2>/dev/null | cut -f1)" \
             "$([ -e "$WP" ] && echo LIVE || echo DEAD)" "$WP"
    done

Then delete under a guard that **refuses** rather than trusting your reading of that list — the
path is the evidence, the hash is not:

    for d in <the hashes>; do
      WP=$(/usr/libexec/PlistBuddy -c "Print :WorkspacePath" "$D/$d/info.plist" 2>/dev/null)
      case "$WP" in */.claude/worktrees/*) : ;;
                    *) echo "REFUSING $d — not a worktree: $WP"; exit 1;; esac
      rm -rf "$D/$d"
    done

⚠️ **A build may be running in the main checkout, and that is fine** — leave ITS directory alone and
delete the rest; done mid-archive 30.8.2026 and the archive finished normally. Watch the word
`xcodebuild` in your own command line, though: the `xcodebuild-lock` hook matches the COMMAND TEXT,
so a compound command that merely contains `pgrep -lx xcodebuild` is blocked while a build is live.

⚠️ **`rm -rf` half-succeeds on a Debug product holding a `_MASReceipt`** (`root:wheel`, written when
a sandboxed Debug build was RUN). Count first — `find "$dir" -user root | wc -l` — and finish with
`sudo` if it is non-zero. A surviving 52 KB shell still satisfies `[ -e ]`, so every later sweep
keeps calling it live.

### 🔴 And the worktree's build is still REGISTERED with the system

This is the half that is not about disk. Every build registers its `.appex` bundles with
LaunchServices, and macOS can then run **the worktree's copy instead of the installed app's**.
*(Measured 30.8.2026: `lsof` showed Safari holding an app extension's `.appex` out of an agent
worktree's Debug build, not out of `/Applications`. The usual visible symptom is the opposite of a
hint — macOS widgets simply vanish from the gallery, which reads as an app bug.)*

    lsof +D "$D/<worktree-hash>" 2>/dev/null | head    # who is holding it right now

Deleting the DerivedData first makes those registrations dead, which is exactly what the sweep
collects — so the order is **delete, then sweep**. 🔴 **Verify by re-count, never by exit code:**
`lsregister -u` returns non-zero even when it worked, and the sweep prints its own `before/after`
line for this reason *(30.8.2026: 238 paths of one app with 219 dead → 13 with 0 dead)*.


## 9. When NOT to isolate

- A change confined to files the other session provably does not hold — and "provably" means you
  read their `git status`, not that a collision seems unlikely.
- A read-only investigation. Isolate anyway if it will end in a commit; you will not enjoy moving
  the work afterwards.
