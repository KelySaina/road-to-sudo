extends Node
## Global signal hub (autoload "EventBus"). Systems emit; UI listens.
## Only cross-cutting notifications live here — systems keep their own
## signals for anything local.

signal command_output(outcome: ExecutionOutcome)
signal narrate(text: String, kind: String)
signal challenge_started(challenge: Challenge)
signal challenge_completed(challenge: Challenge, result: Dictionary)
signal hint_revealed(index: int, text: String)
signal xp_changed(xp: int, rank: Dictionary, progress: float)
signal rank_up(rank: Dictionary)
signal achievement_unlocked(achievement: Dictionary)
signal commands_unlocked(names: Array)
signal session_changed()
signal campaign_finished()
signal menu_requested()
## A command asked to open the full-screen text editor. data: {path, display,
## content, can_write, is_new}. The screen hosting the terminal opens the editor.
signal editor_requested(data: Dictionary)
## A command asked to open the read-only viewer (less / tail -f). data carries
## {mode:"page"|"follow", title, content, ...}. The screen opens the pager.
signal viewer_requested(data: Dictionary)
## A command asked for a (masked) line of input — su's password. data: {label,
## ...}. The screen opens the prompt; the answer goes back via Game.resolve_prompt.
signal prompt_requested(data: Dictionary)

# Adventure (skill-worlds) mode
signal adventure_started()
signal adventure_node(node_id: String)
signal adventure_state_changed()
signal adventure_won()
signal skill_learned(skill: String, lesson: Dictionary)
