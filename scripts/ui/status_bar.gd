extends PanelContainer
## Machine header: host, mode, live CPU/RAM meters derived from the
## simulated process table, and a clock.

var _session: ShellSession
var _cpu_shown := 0.0
var _ram_shown := 0.0
var _tick := 0.0
var _led_phase := 0.0

@onready var led: Label = %Led
@onready var host: Label = %Host
@onready var mode: Label = %Mode
@onready var cpu: Label = %Cpu
@onready var ram: Label = %Ram
@onready var clock: Label = %Clock


func bind(session: ShellSession, mode_text: String) -> void:
	_session = session
	host.text = session.machine.hostname.to_upper()
	mode.text = mode_text
	_refresh(true)


func _process(delta: float) -> void:
	_led_phase += delta
	led.modulate.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_led_phase * 2.2))
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_refresh(false)


func _refresh(snap: bool) -> void:
	clock.text = Time.get_time_string_from_system().substr(0, 5)
	if _session == null:
		return
	var cpu_total := 2.0
	var ram_total := 18.0
	for p in _session.machine.processes:
		cpu_total += float(p.get("cpu", 0.0))
		ram_total += float(p.get("mem", 0.0)) * 4.0
	cpu_total = clampf(cpu_total + randf_range(-1.5, 3.0), 1.0, 100.0)
	ram_total = clampf(ram_total, 1.0, 100.0)
	_cpu_shown = cpu_total if snap else lerpf(_cpu_shown, cpu_total, 0.5)
	_ram_shown = ram_total if snap else lerpf(_ram_shown, ram_total, 0.5)
	_set_meter(cpu, "CPU", _cpu_shown)
	_set_meter(ram, "RAM", _ram_shown)


static func meter_text(label: String, percent: float) -> String:
	var filled := int(round(percent / 10.0))
	return "%s %s%s %3d%%" % [label, "█".repeat(filled), "░".repeat(10 - filled), int(percent)]


func _set_meter(target: Label, label: String, percent: float) -> void:
	target.text = meter_text(label, percent)
	var color := UiTheme.SUCCESS if percent < 60.0 else (UiTheme.WARN if percent < 85.0 else UiTheme.ERROR)
	target.add_theme_color_override("font_color", color)
