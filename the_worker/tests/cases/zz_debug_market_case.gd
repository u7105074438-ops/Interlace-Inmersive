extends TestCase
func run_case() -> void:
	new_run(DEFAULT_SEED, false)
	for s: int in [7, 8]:
		for kind: String in ["", "praise"]:
			new_run(s, false)
			var line: String = "seed %d %s:" % [s, kind]
			for d: int in range(1, 61):
				if d == 1 and kind == "praise":
					NewsFeed.fabricate("company", "NEWS_FABRICATED_PRAISE")
				for _h: int in Market.get_steps_per_day():
					Market.tick_hourly()
				Market.advance_day(Market.get_current_day() + 1)
				NewsFeed.apply_daily_decay()
				if d % 4 == 0:
					line += " d%d P=%.2f s=%.3f inv=%.3f V=%.2f bob=%d tan=%d |" % [d, Market.get_price(), Market.get_sentiment(), Market.get_investor_sentiment(), Market.get_intrinsic_value(), Market.get_investor_confidence("inv_bobby_kerr"), Market.get_investor_confidence("inv_tania_brekke")]
			print(line)
	check(true, "debug")
