<#
2048.ps1 - 2048 Game (PowerShellバージョン)
実行例：.\2048.ps1 -auto_mode 3 -print_mode 1 -one_time 1
2017/01/08 powershell へ移植
2019/01/19 Go最新版に合わせつつデバッグ
2019/01/26 パラメータ対応
2019/02/09 軽微なスペル修正
2019/02/10 スペル修正（D_INIT2→D_INIT_2,D_INIT2→D_INIT_2), calcGap重複削除
#>

Param(
[int] $auto_mode = 4, # >= 0 depth
[int] $calc_gap_mode = 0, # gap計算モード(0:normal 1:端の方が小さければ+1 2:*2 3:+大きい方の値 4:+大きい方の値/10 5:+両方の値)
[int] $print_mode = 100,  #途中経過の表示間隔(0：表示しない)
[int] $print_mode_turbo = 1,
[int] $pause_mode = 0,
[int] $one_time = 1,
[int] $seed = 1,
[int] $turbo_minus_percent       = 55,
[int] $turbo_minus_percent_level = 1,
[int] $turbo_minus_score         = 20000,
[int] $turbo_minus_score_level   = 1,
[int] $turbo_plus_percent        = 10,
[int] $turbo_plus_percent_level  = 1,
[int] $turbo_plus_score          = 20000,
[int] $turbo_plus_score_level    = 1
)

set D_BONUS 10 -option constant 
set D_BONUS_USE_MAX $true -option constant #10固定ではなく最大値とする
set D_GAP_EQUAL 0 -option constant

set D_INIT_2 1 -option constant
set D_INIT_4 2 -option constant
set D_RNDMAX 4 -option constant
set D_GAP_MAX 100000000.0 -option constant
set D_XMAX 4 -option constant
set D_YMAX 4 -option constant
set D_XMAX_1 ($D_XMAX-1) -option constant
set D_YMAX_1 ($D_YMAX-1) -option constant

function make_array([int] $x, [int] $y, [int] $v=0) {
	[int[][]]$ret = new-object int[][] $x
	for ($i = 0; $i -lt $x; $i++) {
		$ret[$i] = new-object int[] $y
		for ($j = 0; $j -lt $y; $j++) {
			$ret[$i][$j] = $v
		}
	}
	$ret
}

$board = make_array $D_XMAX $D_YMAX 0
[int] $sp = 0

$pos_x = (1..($D_XMAX*$D_YMAX))
$pos_y = (1..($D_XMAX*$D_YMAX))
[int] $score = 0
[int] $gen = 0
[int] $count_2 = 0
[int] $count_4 = 0
[int] $count_getGap = 0
[int] $count_calcGap = 0

[DateTime] $start_time = (Get-Date)
[DateTime] $last_time = (Get-Date)
[DateTime] $total_start_time = 0
[DateTime] $total_last_time = 0

[int] $count = 1
[int] $sum_score = 0
[int] $max_score = 0
[int] $max_seed = 0
[int] $min_score = $D_GAP_MAX
[int] $min_seed = 0
[double] $ticks_per_sec = 10000000

function main {
	Write-Host "auto_mode=$auto_mode"
	Write-Host "calc_gap_mode=$calc_gap_mode"
	Write-Host "print_mode=$print_mode"
	Write-Host "print_mode_turbo=$print_mode_turbo"
	Write-Host "pause_mode=$pause_mode"
	Write-Host "seed=$seed"
	Write-Host "one_time=$one_time"
	Write-Host "turbo_minus_percent=$turbo_minus_percent"
	Write-Host "turbo_minus_percent_level=$turbo_minus_percent_level"
	Write-Host "turbo_minus_score=$turbo_minus_score"
	Write-Host "turbo_minus_score_level=$turbo_minus_score_level"
	Write-Host "turbo_plus_percent=$turbo_plus_percent"
	Write-Host "turbo_plus_percent_level=$turbo_plus_percent_level"
	Write-Host "turbo_plus_score=$turbo_plus_score"
	Write-Host "turbo_plus_score_level=$turbo_plus_score_level"

	if ($seed -gt 0) {
		$dmy = Get-Random -SetSeed $seed
	} else {
		$dmy = Get-Random -SetSeed ((getTime).Ticks % [int]::MaxValue)
	}
	$script:total_start_time = getTime
	init_game
	while ($true) {
		[double] $gap = moveAuto $auto_mode
		$script:gen++
		$tmp = appear
		$tmp = disp $gap ($print_mode -gt 0 -and
			(($gen % $print_mode) -eq 0 -or
				($print_mode_turbo -eq 1 -and $score -gt $turbo_minus_score) -or
				($print_mode_turbo -eq 2 -and $score -gt $turbo_plus_score)))
		if (isGameOver) {
			$sc = getScore
			$script:sum_score += $sc
			if ($sc -gt $max_score) {
				$script:max_score = $sc
				$script:max_seed = $seed
			}
			if ($sc -lt $min_score) {
				$script:min_score = $sc
				$script:min_seed = $seed
			}
			Write-Host "Game Over! (level=$auto_mode seed=$seed) $((getTime).ToString("yyyy/MM/dd HH:mm:ss")) #$count Ave.=$([int]($sum_score/$count)) Max=$max_score(seed=$max_seed) Min=$min_score(seed=$min_seed)`ngetGap=$count_getGap calcGap=$count_calcGap ${D_BONUS},${D_GAP_EQUAL} ${turbo_minus_percent}%,${turbo_minus_percent_level} ${turbo_minus_score},${turbo_minus_score_level} ${turbo_plus_percent}%,${turbo_plus_percent_level} ${turbo_plus_score},${turbo_plus_score_level} ${print_mode_turbo} calc_gap_mode=${calc_gap_mode}"
			disp $gap $true
			if ($one_time -gt 0) {
				$one_time--;
				if ($one_time -eq 0) {
					break
				}
			}
			if ($pause_mode -gt 0) {
				[string] $key
				#$key=[Console]::ReadKey($true)
				$key = Read-Host "q=Quit"
				if ($key -eq "q" -or $key -eq "Q") {
					break
				}
			}
			$script:seed++
			$dmy = Get-Random -SetSeed $seed
			init_game
			$script:count++
		}
	}
	$script:total_last_time = getTime
	Write-Host "Total time = $(($script:total_last_time.Ticks-$script:total_start_time.Ticks)/$ticks_per_sec) (sec)"
}

function getCell([int] $x, [int] $y) {
	$board[$x][$y]
}

function setCell([int] $x, [int] $y, [int] $n) {
	$board[$x][$y] = $n
}

function clearCell([int] $x, [int] $y) {
	$tmp = setCell $x $y 0
}

function copyCell([int] $x1, [int] $y1, [int] $x2, [int] $y2) {
	$ret = getCell $x1 $y1
	$tmp = setCell $x2 $y2 $ret
}

function moveCell([int] $x1, [int] $y1, [int] $x2, [int] $y2) {
	$tmp = copyCell $x1 $y1 $x2 $y2
	$tmp = clearCell $x1 $y1
}

function addCell([int] $x1, [int] $y1, [int] $x2, [int] $y2) {
	$board[$x2][$y2]++
	$tmp = clearCell $x1 $y1
	if ($sp -lt 1) {
		$val = getCell $x2 $y2
		[int] $tmp_score = 1 -shl $val
		addScore $tmp_score
	}
}

function isEmpty([int] $x, [int] $y) {
	$ret = getCell $x $y
	return $ret -eq  0
}

function isNotEmpty([int] $x, [int] $y) {
	(getCell $x $y) -ne  0
}

function isGameOver {
	($ret, $dmy, $dmy) = isMovable
	if ($ret) {
		return $false
	} else {
		return $true
	}
}

function getScore {
	$score
}

function setScore([int] $sc) {
	$script:score = $sc
	getScore
}

function addScore([int] $sc) {
	$script:score += $sc
	getScore
}

function clear_board() {
	for ([int] $y = 0; $y -lt $D_YMAX; $y++) {
		for ([int] $x = 0; $x -lt $D_XMAX; $x++) {
			$tmp = clearCell $x $y
		}
	}
}

function disp([double] $gap, $debug) {
	[string] $s = ""
	$now = getTime
	$cur_time = ($now.Ticks-$script:last_time.Ticks)/$ticks_per_sec
	$all_time = ($now.Ticks-$script:start_time.Ticks)/$ticks_per_sec
	$cur_time_str = $cur_time.ToString("0.00")
	$all_time_str = $all_time.ToString("0.0")
	$gap_str = $gap.ToString("0.000000")
	$now_str = $now.ToString("yyyy/MM/dd HH:mm:ss")
	$per_2 = ($count_2 / ($count_2 + $count_4) * 100).ToString("0.00")
	if ($count -eq 0) {
		Write-Host "[${count}:$gen] $(getScore) ($cur_time_str/$all_time_str sec) $gap_str $now_str seed=$seed 2=$($per_2)%`r" -NoNewLine
	} else {
		$ave_str = (($sum_score + $(getScore))/$count).ToString("0.0")
		Write-Host "[${count}:$gen] $(getScore) ($cur_time_str/$all_time_str sec) $gap_str $now_str seed=$seed 2=$($per_2)% Ave.=${ave_str}`r" -NoNewLine
	}
	$script:last_time = $now
	if ($debug) {
		Write-Host ""
		for ([int] $y = 0; $y -lt $D_YMAX; $y++) {
			$s = ""
			for ([int] $x = 0; $x -lt $D_XMAX; $x++) {
				[int] $v = getCell $x $y
				if ($v -gt 0) {
					[int] $val = 1 -shl $v
					$s += $val.ToString("0").PadLeft(5, " ") + " "
				} else {
					$s += "    . "
				}
			}
			Write-Host "$s"
		}
	}
}

function init_game() {
	$script:gen = 1
	$tmp = setScore 0
	$script:start_time = (Get-Date)
	$script:last_time = $script:start_time
	$tmp = clear_board
	$tmp = appear
	$tmp = appear
	disp 0.0 ($print_mode -gt 0)
}

function getTime {
	return (Get-Date)
}

function appear {
	[int] $n = 0
	for ($y = 0; $y -lt $D_YMAX; $y++) {
		for ($x = 0; $x -lt $D_XMAX; $x++) {
			if (isEmpty $x $y) {
				$pos_x[$n] = $x
				$pos_y[$n] = $y
				$n++
			}
		}
	}
	if ($n -gt 0) {
		[int] $v
		$i = Get-Random $count
		[int] $val = Get-Random 65535
		if (($val % $D_RNDMAX) -ge 1) {
			$v = $D_INIT_2
			$script:count_2++
		} else {
			$v = $D_INIT_4
			$script:count_4++
		}
		[int] $x = $pos_x[$i]
		[int] $y = $pos_y[$i]
		setCell $x $y $v
		return $true
	}
	return $false
}

function countEmpty {
	$ret = 0
	for ([int] $y = 0; $y -lt $D_YMAX; $y++) {
		for ([int] $x = 0; $x -lt $D_XMAX; $x++) {
			$isempty = isEmpty $x $y
			if ($isempty) {
				$ret++
			}
		}
	}
	return $ret
}

function move_up {
	[int] $move = 0
	[int] $yLimit = 0
	[int] $yNext = 0
	for ([int] $x = 0; $x -lt $D_XMAX; $x++) {
		$yLimit = 0
		for ([int] $y = 1; $y -lt $D_YMAX; $y++) {
			$isnotempty = isNotEmpty $x $y
			if ($isnotempty) {
				$yNext = $y - 1
				while ($yNext -ge $yLimit) {
					$isnotempty = isNotEmpty $x $yNext
					if ($isnotempty) {
						break
					}
					if ($yNext -eq 0) {
						break
					}
					$yNext = $yNext - 1
				}
				if ($yNext -lt $yLimit) {
					$yNext = $yLimit
				}
				$isempty = isEmpty $x $yNext
				if ($isempty) {
					$tmp = moveCell $x $y $x $yNext
					$move++
				} else {
					[int] $val1 = getCell $x $yNext
					[int] $val2 = getCell $x $y
					if ($val1 -eq $val2) {
						$tmp = addCell $x $y $x $yNext
						$move++
						$yLimit = $yNext + 1
					} else {
						[int] $yNext1 = $yNext+1
						if ($yNext1 -ne $y) {
							$tmp = moveCell $x $y $x $yNext1
							$move++
							$yLimit = $yNext1
						}
					}
				}
			}
		}
	}
	return $move
}

function move_left {
	[int] $move = 0
	[int] $xLimit = 0
	[int] $xNext = 0
	for ([int] $y = 0; $y -lt $D_YMAX; $y++) {
		$xLimit = 0
		for ([int] $x = 1; $x -lt $D_XMAX; $x++) {
			$isnotempty = isNotEmpty $x $y
			if ($isnotempty) {
				$xNext = $x - 1
				while ($xNext -ge $xLimit) {
					$isnotempty = isNotEmpty $xNext $y
					if ($isnotempty) {
						break
					}
					if ($xNext -eq 0) {
						break
					}
					$xNext = $xNext - 1
				}
				if ($xNext -lt $xLimit) {
					$xNext = $xLimit
				}
				$isempty = isEmpty $xNext $y
				if ($isempty) {
					$tmp = moveCell $x $y $xNext $y
					$move++
				} else {
					[int] $val1 = getCell $xNext $y
					[int] $val2 = getCell $x $y
					if ($val1 -eq $val2) {
						$tmp = addCell $x $y $xNext $y
						$move++
						$xLimit = $xNext + 1
					} else {
						[int] $xNext1 = $xNext + 1
						if ($xNext1 -ne $x) {
							$tmp = moveCell $x $y $xNext1 $y
							$move++
							$xLimit = $xNext1
						}
					}
				}
			}
		}
	}
	return $move
}

function move_down {
	[int] $move = 0
	[int] $yLimit = 0
	[int] $yNext = 0
	for ([int] $x = 0; $x -lt $D_XMAX; $x++) {
		$yLimit = $D_YMAX - 1
		for ([int] $y = $D_YMAX - 2; $y -ge 0; $y--) {
			$isnotempty = isNotEmpty $x $y
			if ($isnotempty) {
				$yNext = $y + 1
				while ($yNext -le $yLimit) {
					$isnotempty = isNotEmpty $x $yNext
					if ($isnotempty) {
						break
					}
					if ($yNext -eq $D_YMAX_1) {
						break
					}
					$yNext = $yNext + 1
				}
				if ($yNext -gt $yLimit) {
					$yNext = $yLimit
				}
				$isempty = isEmpty $x $yNext
				if ($isempty) {
					$tmp = moveCell $x $y $x $yNext
					$move++
				} else {
					[int] $val1 = getCell $x $yNext
					[int] $val2 = getCell $x $y
					if ($val1 -eq $val2) {
						$tmp = addCell $x $y $x $yNext
						$move++
						$yLimit = $yNext - 1
					} else {
						$yNext1 = $yNext - 1
						if ($yNext1 -ne $y) {
							$tmp = moveCell $x $y $x $yNext1
							$move++
							$yLimit = $yNext1
						}
					}
				}
			}
		}
	}
	return $move
}

function move_right {
	[int] $move = 0
	[int] $xLimit = 0
	[int] $xNext = 0
	for ([int] $y = 0; $y -lt $D_YMAX; $y++) {
		$xLimit = $D_XMAX - 1
		for ([int] $x = $D_XMAX - 2; $x -ge 0; $x--) {
			$isnotempty = isNotEmpty $x $y
			if ($isnotempty) {
				$xNext = $x + 1
				while ($xNext -le $xLimit) {
					$isnotempty = isNotEmpty $xNext $y
					if ($isnotempty) {
						break
					}
					if ($xNext -eq $D_XMAX_1) {
						break
					}
					$xNext = $xNext + 1
				}
				if ($xNext -gt $xLimit) {
					$xNext = $xLimit
				}
				$isempty = isEmpty $xNext $y
				if ($isempty) {
					$tmp = moveCell $x $y $xNext $y
					$move++
				} else {
					$val1 = getCell $xNext $y
					$val2 = getCell $x $y
					if ($val1 -eq $val2) {
						$tmp = addCell $x $y $xNext $y
						$move++
						$xLimit = $xNext - 1
					} else {
						$xNext1 = $xNext - 1
						if ($xNext1 -ne $x) {
							$tmp = moveCell $x $y $xNext1 $y
							$move++
							$xLimit = $xNext1
						}
					}
				}
			}
		}
	}
	return $move
}

function moveAuto($autoMode) {
	$empty = countEmpty
	$sc = getScore
	if ($empty -ge $D_XMAX*$D_YMAX*$turbo_minus_percent/100) {
		$autoMode -= $turbo_minus_percent_level
	} elseif ($empty -lt $D_XMAX*$D_YMAX*$turbo_plus_percent/100) {
		$autoMode += $turbo_plus_percent_level
	}
	if ($sc -lt $turbo_minus_score) {
		$autoMode -= $turbo_minus_score_level
	} elseif ($sc -ge $turbo_plus_score) {
		$autoMode += $turbo_plus_score_level
	}
	$ret = moveBest $autoMode $true
	return $ret
}

function moveBest([int] $nAutoMode, $move) {
	[double] $nGap = 0.0
	[double] $nGapBest = $D_GAP_MAX
	[int] $nDirBest = 0
	[int] $nDir = 0
	[int[][]]$board_bak = make_array $D_XMAX $D_YMAX
	$tmp = copyBoard $board $board_bak
	$script:sp++
	$nGapBest = $D_GAP_MAX
	$val = move_up
	if ($val -gt 0) {
		$nDir = 1
		$nGap = getGap $nAutoMode $nGapBest
		if ($nGap -lt $nGapBest) {
			$nGapBest = $nGap
			$nDirBest = 1
		}
	}
	$tmp = copyBoard $board_bak $board
	$val = move_left
	if ($val -gt 0) {
		$nDir = 2
		$nGap = getGap $nAutoMode $nGapBest
		if ($nGap -lt $nGapBest) {
			$nGapBest = $nGap
			$nDirBest = 2
		}
	}
	$tmp = copyBoard $board_bak $board
	$val = move_down
	if ($val -gt 0) {
		$nDir = 3
		$nGap = getGap $nAutoMode $nGapBest
		if ($nGap -lt $nGapBest) {
			$nGapBest = $nGap
			$nDirBest = 3
		}
	}
	$tmp = copyBoard $board_bak $board
	$val = move_right
	if ($val -gt 0) {
		$nDir = 4
		$nGap = getGap $nAutoMode $nGapBest
		if ($nGap -lt $nGapBest) {
			$nGapBest = $nGap
			$nDirBest = 4
		}
	}
	$tmp = copyBoard $board_bak $board
	$script:sp--
	if ($move) {
		if ($nDirBest -eq 0) {
			Write-Host "***** Give UP *****"
			$nDirBest = $nDir
		}
		switch ($nDirBest) {
			1 {
				$tmp = move_up
				break
			}
			2 {
				$tmp = move_left
				break
			}
			3 {
				$tmp = move_down
				break
			}
			4 {
				$tmp = move_right
				break
			}
		}
	}
	return $nGapBest
}

function copyBoard($a, $b) {
	for ([int] $x = 0; $x -lt $D_XMAX; $x++) {
		for ([int] $y = 0; $y -lt $D_YMAX; $y++) {
			$b[$x][$y] = $a[$x][$y]
		}
	}
}

function getGap([int] $nAutoMode, [double] $nGapBest) {
	$script:count_getGap++
	[double] $ret = 0.0
	($movable, $nEmpty, $nBonus) = isMovable
	if (-not $movable) {
		$ret = $D_GAP_MAX
	} elseif ($nAutoMode -le 1) {
		$ret = getGap1 $nGapBest $nEmpty $nBonus
	} else {
		$alpha = $nGapBest * $nEmpty #累積がこれを超えれば、平均してもnGapBestを超えるので即枝刈りする
		for ([int] $x = 0; $x -lt $D_XMAX; $x++) {
			for ([int] $y = 0; $y -lt $D_YMAX; $y++) {
				if (isEmpty $x $y) {
					$nAutoMode1 = $nAutoMode-1
					$tmp = setCell $x $y $D_INIT_2
					$best = moveBest $nAutoMode1 $false
					$ret += $best * ($D_RNDMAX - 1) / $D_RNDMAX
					if ($ret -ge $alpha) {
						return $D_GAP_MAX
					}
					$tmp = setCell $x $y $D_INIT_4
					$best = moveBest $nAutoMode1 $false
					$ret += $best / $D_RNDMAX
					if ($ret -ge $alpha) {
						return $D_GAP_MAX
					}
					$tmp = clearCell $x $y
				}
			}
		}
		$ret /= $nEmpty
	}
	return $ret
}

function getGap1([double] $nGapBest, [int] $nEmpty, [double] $nBonus) {
	[double] $ret = 0.0
	[double] $ret_appear = 0.0
	$alpha = $nGapBest * $nBonus
	$edgea = $False
	$edgeb = $False
	for ([int] $x = 0; $x -lt $D_XMAX; $x++) {
		for ([int] $y = 0; $y -lt $D_YMAX; $y++) {
			$v = getCell $x $y
			$edgea = ($x -eq 0 -or $y -eq 0 -or $x -eq $D_XMAX_1 -or $y -eq $D_YMAX_1)
			if ($v -gt 0) {
				if ($x -lt $D_XMAX_1) {
					$x1 = getCell ($x+1) $y
					$edgeb = ($y -eq 0) -or ($x+1 -eq $D_XMAX_1 -or $y -eq $D_YMAX_1)
					if ($x1 -gt 0) {
						$ret += calcGap $v $x1 $edgea $edgeb
					} else {
						$calcGap = calcGap $v $D_INIT_2 $edgea $edgeb
						$ret_appear += $calcGap * ($D_RNDMAX - 1) / $D_RNDMAX
						$calcGap = calcGap $v $D_INIT_4 $edgea $edgeb
						$ret_appear += $calcGap / $D_RNDMAX
					}
				}
				if ($y -lt $D_YMAX_1) {
					$y1 = getCell $x ($y+1)
					$edgeb = ($x -eq 0) -or ($x -eq $D_XMAX_1 -or $y+1 -eq $D_YMAX_1)
					if ($y1 -gt 0) {
						$ret += calcGap $v $y1 $edgea $edgeb
					} else {
						$calcGap = calcGap $v $D_INIT_2 $edgea $edgeb
						$ret_appear += $calcGap * ($D_RNDMAX - 1) / $D_RNDMAX
						$calcGap = calcGap $v $D_INIT_4 $edgea $edgeb
						$ret_appear += $calcGap / $D_RNDMAX
					}
				}
			}
			else {
				if ($x -lt $D_XMAX_1) {
					$x1 = getCell ($x+1) $y
					$edgeb = ($y -eq 0) -or ($x+1 -eq $D_XMAX_1 -or $y -eq $D_YMAX_1)
					if ($x1 -gt 0) {
						$calcGap = calcGap $D_INIT_2 $x1 $edgea $edgeb
						$ret_appear += $calcGap * ($D_RNDMAX - 1) / $D_RNDMAX
						$calcGap = calcGap $D_INIT_4 $x1 $edgea $edgeb
						$ret_appear += $calcGap / $D_RNDMAX
					}
				}
				if ($y -lt $D_YMAX_1) {
					$y1 = getCell $x ($y+1)
					$edgeb = ($x -eq 0) -or ($x -eq $D_XMAX_1 -or $y+1 -eq $D_YMAX_1)
					if ($y1 -gt 0) {
						$calcGap = calcGap $D_INIT_2 $y1 $edgea $edgeb
						$ret_appear += $calcGap * ($D_RNDMAX - 1) / $D_RNDMAX
						$calcGap = calcGap $D_INIT_4 $y1 $edgea $edgeb
						$ret_appear += $calcGap / $D_RNDMAX
					}
				}
			}
			if (($ret + ($ret_appear/$nEmpty)) -gt $alpha) {
				return $D_GAP_MAX
			}
		}
	}
	$ret += $ret_appear / $nEmpty
	$ret /= $nBonus
	return $ret
}

function calcGap([int] $a, [int] $b, $edgea, $edgeb) {
	$script:count_calcGap++
	[double] $ret = 0
	if ($a -gt $b) {
		$ret = $a - $b
		if ($calc_gap_mode -lt 0 -and -not $edgea -and $edgeb) {
			switch ($calc_gap_mode) {
				1 {
					$ret += 1
					break
				}
				2 {
					$ret *= 2
					break
				}
				3 {
					$ret += $a
					break
				}
				4 {
					$ret += $a/10
					break
				}
				5 {
					$ret += $a+$b
					break
				}
			}
		}
	} elseif ($a -lt $b) {
		$ret = $b - $a
		if ($calc_gap_mode -gt 0 -and $edgea -and -not $edgeb) {
			switch ($calc_gap_mode) {
				1 {
					$ret += 1
					break
				}
				2 {
					$ret *= 2
					break
				}
				3 {
					$ret += $a
					break
				}
				4 {
					$ret += $a/10
					break
				}
				5 {
					$ret += $a+$b
					break
				}
			}
		}
	} else {
		$ret = $D_GAP_EQUAL
	}
	return $ret
}

function isMovable {
	[bool] $ret = $false #動けるか？
	[int] $nEmpty = 0 #空きの数
	[double] $nBonus = 1.0 #ボーナス（隅が最大値ならD_BONUS）
	[int] $max_x = 0
	[int] $max_y = 0
	[int] $max = 0
	for ([int] $y = 0; $y -lt $D_YMAX; $y++) {
		for ([int] $x = 0; $x -lt $D_XMAX; $x++) {
			$val = getCell $x $y
			if ($val -eq 0) {
				$ret = $true
				$nEmpty++
			} else {
				if ($val -gt $max) {
					$max = $val
					$max_x = $x
					$max_y = $y
				}
				if (-not $ret) {
					if ($x -lt $D_XMAX_1) {
						$x1 = getCell ($x+1) $y
						if ($val -eq $x1 -or $x1 -eq 0) {
							$ret = $true
						}
					}
					if ($y -lt $D_YMAX_1) {
						$y1 = getCell $x ($y+1)
						if ($val -eq $y1 -or $y1 -eq 0) {
							$ret = $true
						}
					}
				}
			}
		}
	}
	if (($max_x -eq 0 -or $max_x -eq $D_XMAX_1) -and
		($max_y -eq 0 -or $max_y -eq $D_YMAX_1)) {
		if ($D_BONUS_USE_MAX) {
			$nBonus = $max
		} else {
			$nBonus = $D_BONUS
		}
	}
	return ($ret, $nEmpty, $nBonus)
}

main

