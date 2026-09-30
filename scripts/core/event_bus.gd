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

# Adventure (RPG) mode
signal adventure_started()
signal adventure_node(node_id: String)
signal adventure_state_changed()
signal adventure_won()
signal player_damaged(amount: int, hp: int)
signal player_rebooted()
