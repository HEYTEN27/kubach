extends GutTest
## Мини-игра ковки: масса сохраняется, форма достижима, холодный металл трескается.


func test_mass_conserved() -> void:
	var g := ForgeGame.new([2, 4, 6, 8, 8, 6, 4, 2])
	for i in 20:
		g.strike(i % 8, i % 3 != 0)
	var sum := 0.0
	for v in g.shape:
		sum += v
	assert_almost_eq(sum, 40.0, 0.01)


func test_reaching_target_scores_high() -> void:
	var g := ForgeGame.new([5, 5, 5, 5, 5, 5, 5, 5])
	assert_almost_eq(g.score(), 1.0, 0.001, "плоская цель — уже готово")
	g = ForgeGame.new([6, 4, 5, 5, 5, 5, 5, 5])
	assert_lt(g.score(), 1.0)
	g.strike(1, true)   # 1 опускается, 0 и 2 поднимаются
	g.strike(2, true)
	assert_gt(g.score(), 0.7)


func test_cold_strikes_crack() -> void:
	var g := ForgeGame.new([5, 5, 5, 5, 5, 5, 5, 5])
	g.cool(100.0)
	g.strike(3)
	assert_eq(g.cracks, 1)
	g.reheat()
	g.strike(3)
	assert_eq(g.cracks, 1)
	assert_eq(g.reheats, 1)
