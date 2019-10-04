/*
2048.cs - 2048 Game

2017/01/07 pprof効果がわかるようにgetGapからlevel=0を別関数に分離(getGap1)
2017/01/21 memprofile オプション追加 2048.exe -memprofile=6060 で実行し、http://localhost:6060/debug/pprof/heap?debug=1 を開く
2017/01/24 getGapをチューニング（appear途中で最大値を超えたら枝刈りで読み中断）
2017/01/27 getGap,getGap1をチューニング（appear前のGapを1度計算しておいてから、各appearによる差分のみを加算）
2017/02/11 calcGapをチューニング（端と端以外のGap計算時に端の方が小さければGapを増やす。-calc_gap_mode追加）
2017/02/12 D_BONUS_POINT_MAX, D_BONUS2廃止
2019/09/29 Go版からC#版に移植開始
2019/10/04 Go版からC#版に移植完了
 */
 
using System;

public static class Game2048
{
    static int auto_mode = 4; // >=0 depth
    static int calc_gap_mode = 0; // gap計算モード(0:normal 1:端の方が小さければ+1 2:*2 3:+大きい方の値 4:+大きい方の値/10 5:+両方の値)
    static int print_mode = 100; // 途中経過の表示間隔(0：表示しない)
    static int print_mode_turbo = 1;
    static int pause_mode = 0;
    static int one_time = 1; // 繰り返し回数
    static int seed = 1;
    static int turbo_minus_percent       = 55;
    static int turbo_minus_percent_level = 1;
    static int turbo_minus_score         = 20000;
    static int turbo_minus_score_level   = 1;
    static int turbo_plus_percent        = 10;
    static int turbo_plus_percent_level  = 1;
    static int turbo_plus_score          = 200000;
    static int turbo_plus_score_level    = 1;

    const int D_BONUS = 10;
    static bool D_BONUS_USE_MAX = true; //10固定ではなく最大値とする
    const int GAP_EQUAL = 0;

    const int INIT2 = 1;
    const int INIT4 = 2;
    const int RNDMAX = 4;
    const double GAP_MAX = 100000000.0;
    const int XMAX = 4;
    const int YMAX = 4;
    const int XMAX_1 = (XMAX-1);
    const int YMAX_1 = (YMAX-1);

    static int [,] board = new int[XMAX,YMAX];
    static int sp = 0;

    static int [] pos_x = new int[XMAX*YMAX];
    static int [] pos_y = new int[XMAX*YMAX];
    static int [] pos_val = new int[XMAX*YMAX];
    static int score;
    static int gen;
    static int count_2 = 0;
    static int count_4 = 0;
    static ulong count_calcGap = 0;
    static ulong count_getGap = 0;

    static long start_time;
    static long last_time;
    static long total_start_time;
    static long total_last_time;

    static int count = 1;
    static int sum_score = 0;
    static int max_score = 0;
    static long max_seed = 0;
    static int min_score = (int)GAP_MAX;
    static long min_seed = 0;
    static double ticks_per_sec = 10000000;

    static Random rnd; // random number generator

    static int getCell(int x, int y) {
        return (board[x,y]);
    }

    static int setCell(int x, int y, int n) {
        board[x,y] = (n);
        return (n);
    }

    static void clearCell(int x, int y) {
        setCell(x, y, 0);
    }

    static int copyCell(int x1, int y1, int x2, int y2) {
        return (setCell(x2, y2, getCell(x1, y1)));
    }

    static void moveCell(int x1, int y1, int x2, int y2) {
        copyCell(x1, y1, x2, y2);
        clearCell(x1, y1);
    }

    static void addCell(int x1, int y1, int x2, int y2) {
        board[x2,y2]++;
        clearCell(x1, y1);
        if (sp < 1) {
            addScore((int)(((uint)1) << (getCell(x2, y2))));
        }
    }

    static bool isEmpty(int x, int y) {
        return (getCell(x, y) == 0);
    }

    static bool isNotEmpty(int x, int y) {
        return (!isEmpty(x, y));
    }

    static bool isGameOver() {
        int _nEmpty = 0;
        double _nBonus = 0.0;
        bool ret = isMovable(ref _nEmpty, ref _nBonus);
        if (ret) {
            return false;
        } else {
            return true;
        }
    }

    static int getScore() {
        return (score);
    }

    static int setScore(int sc) {
        score = (sc);
        return (score);
    }

    static int addScore(int sc) {
        score += (sc);
        return score;
    }

    static void clear() {
        for (int y = 0; y < YMAX; y++) {
            for (int x = 0; x < XMAX; x++) {
                clearCell(x, y);
            }
        }
    }

    static void disp(double gap, bool debug) {
        long now = DateTime.Now.Ticks;
        if (count == 0) {
            Console.Write("[{0}:{1}] {2} ({3:f2}/{4:f1} sec) {5:f6} {6} seed={7} 2={8:f2}%\r", count, gen, getScore(), (double)(now-last_time)/ticks_per_sec, (double)(now-start_time)/ticks_per_sec, gap, getTime(), seed, (double)(count_2)/(double)(count_2+count_4)*100);
        } else {
            Console.Write("[{0}:{1}] {2} ({3:f2}/{4:f1} sec) {5:f6} {6} seed={7} 2={8:f2}% Ave.={9}\r", count, gen, getScore(), (double)(now-last_time)/ticks_per_sec, (double)(now-start_time)/ticks_per_sec, gap, getTime(), seed, (double)(count_2)/(double)(count_2+count_4)*100, (sum_score+getScore())/count);
        }
        last_time = now;
        if (debug) {
            Console.Write("\n");
            for (int y = 0; y < YMAX; y++) {
                for (int x = 0; x < XMAX; x++) {
                    int v = getCell(x, y);
                    if (v > 0) {
                        Console.Write("{0,5} ", (uint)1<<(v));
                    } else {
                        Console.Write("{0,5} ", ".");
                    }
                }
                Console.Write("\n");
            }
        }
    }

    static void init_game() {
        gen = 1;
        setScore(0);
        start_time = DateTime.Now.Ticks;
        last_time = start_time;
        clear();
        appear();
        appear();
        count_2 = 0;
        count_4 = 0;
        count_calcGap = 0;
        count_getGap = 0;
        disp(0.0, print_mode == 1);
    }

    static string getTime() {
//        return DateTime.Now.ToString("yyyy/MM/dd HH:mm:ss");
        return DateTime.Now.ToString();
    }

    static bool appear() {
        int n = 0;
        for (int y = 0; y < YMAX; y++) {
            for (int x = 0; x < XMAX; x++) {
                if (isEmpty(x, y)) {
                    pos_x[n] = x;
                    pos_y[n] = y;
                    n++;
                }
            }
        }
        if (n> 0) {
            int v;
            int i = rnd.Next(65535) % n;
            if ((rnd.Next(65535) % RNDMAX) >= 1) {
                v = INIT2;
                count_2++;
            } else {
                v = INIT4;
                count_4++;
            }
            int x = pos_x[i];
            int y = pos_y[i];
            setCell(x, y, v);
            return true;
        }
        return false;
    }

    static int countEmpty() {
        int ret = 0;
        for (int y = 0; y < YMAX; y++) {
            for (int x = 0; x < XMAX; x++) {
                if (isEmpty(x, y)) {
                    ret++;
                }
            }
        }
        return ret;
    }

    static int move_up() {
        int move = 0;
        int yLimit;
        int yNext;
        for (int x = 0; x < XMAX; x++) {
            yLimit = 0;
            for (int y = 1; y < YMAX; y++) {
                if (isNotEmpty(x, y)) {
                    yNext = y - 1;
                    while (yNext >= yLimit) {
                        if (isNotEmpty(x, yNext)) {
                            break;
                        }
                        if (yNext == 0) {
                            break;
                        }
                        yNext = yNext - 1;
                    }
                    if (yNext < yLimit) {
                        yNext = yLimit;
                    }
                    if (isEmpty(x, yNext)) {
                        moveCell(x, y, x, yNext);
                        move++;
                    } else {
                        if (getCell(x, yNext) == getCell(x, y)) {
                            addCell(x, y, x, yNext);
                            move++;
                            yLimit = yNext + 1;
                        } else {
                            if (yNext+1 != y) {
                                moveCell(x, y, x, yNext+1);
                                move++;
                                yLimit = yNext + 1;
                            }
                        }
                    }
                }
            }
        }
        return move;
    }

    static int move_left() {
        int move = 0;
        int xLimit;
        int xNext;
        for (int y = 0; y < YMAX; y++) {
            xLimit = 0;
            for (int x = 1; x < XMAX; x++) {
                if (isNotEmpty(x, y)) {
                    xNext = x - 1;
                    while (xNext >= xLimit) {
                        if (isNotEmpty(xNext, y)) {
                            break;
                        }
                        if (xNext == 0) {
                            break;
                        }
                        xNext = xNext - 1;
                    }
                    if (xNext < xLimit) {
                        xNext = xLimit;
                    }
                    if (isEmpty(xNext, y)) {
                        moveCell(x, y, xNext, y);
                        move++;
                    } else {
                        if (getCell(xNext, y) == getCell(x, y)) {
                            addCell(x, y, xNext, y);
                            move++;
                            xLimit = xNext + 1;
                        } else {
                            if (xNext+1 != x) {
                                moveCell(x, y, xNext+1, y);
                                move++;
                                xLimit = xNext + 1;
                            }
                        }
                    }
                }
            }
        }
        return move;
    }

    static int move_down() {
        int move = 0;
        int yLimit;
        int yNext;
        for (int x = 0; x < XMAX; x++) {
            yLimit = YMAX_1;
            for (int y = YMAX - 2; y >= 0; y--) {
                if (isNotEmpty(x, y)) {
                    yNext = y + 1;
                    while (yNext <= yLimit) {
                        if (isNotEmpty(x, yNext)) {
                            break;
                        }
                        if (yNext == YMAX_1) {
                            break;
                        }
                        yNext = yNext + 1;
                    }
                    if (yNext > yLimit) {
                        yNext = yLimit;
                    }
                    if (isEmpty(x, yNext)) {
                        moveCell(x, y, x, yNext);
                        move++;
                    } else {
                        if (getCell(x, yNext) == getCell(x, y)) {
                            addCell(x, y, x, yNext);
                            move++;
                            yLimit = yNext - 1;
                        } else {
                            if (yNext-1 != y) {
                                moveCell(x, y, x, yNext-1);
                                move++;
                                yLimit = yNext - 1;
                            }
                        }
                    }
                }
            }
        }
        return move;
    }

    static int move_right() {
        int move = 0;
        int xLimit;
        int xNext;
        for (int y = 0; y < YMAX; y++) {
            xLimit = XMAX_1;
            for (int x = XMAX - 2; x >= 0; x--) {
                if (isNotEmpty(x, y)) {
                    xNext = x + 1;
                    while (xNext <= xLimit) {
                        if (isNotEmpty(xNext, y)) {
                            break;
                        }
                        if (xNext == XMAX_1) {
                            break;
                        }
                        xNext = xNext + 1;
                    }
                    if (xNext > xLimit) {
                        xNext = xLimit;
                    }
                    if (isEmpty(xNext, y)) {
                        moveCell(x, y, xNext, y);
                        move++;
                    } else {
                        if (getCell(xNext, y) == getCell(x, y)) {
                            addCell(x, y, xNext, y);
                            move++;
                            xLimit = xNext - 1;
                        } else {
                            if (xNext-1 != x) {
                                moveCell(x, y, xNext-1, y);
                                move++;
                                xLimit = xNext - 1;
                            }
                        }
                    }
                }
            }
        }
        return move;
    }

    static double moveAuto(int autoMode) {
        int empty = countEmpty();
        int sc = getScore();
        if (empty >= XMAX*YMAX*turbo_minus_percent/100) {
            autoMode -= turbo_minus_percent_level;
        } else if (empty < XMAX*YMAX*turbo_plus_percent/100) {
            autoMode += turbo_plus_percent_level;
        }
        if (sc < turbo_minus_score) {
            autoMode -=turbo_minus_score_level;
        } else if (sc >= turbo_plus_score) {
            autoMode += turbo_plus_score_level;
        }
        return moveBest(autoMode, true);
    }

    static void copy_board(int [,] to, int [,] from) {
        for (int y = 0; y < YMAX; y++) {
            for (int x = 0; x < XMAX; x++) {
                to[x,y] = from[x,y];
            }
        }
    }

    static double moveBest(int nAutoMode, bool move)  {
        double nGap;
        double nGapBest;
        int nDirBest = 0;
        int nDir = 0;
        int [,] board_bak = new int[XMAX,YMAX];
        copy_board(board_bak, board);
        sp++;
        nGapBest = GAP_MAX;
        if (move_up() > 0) {
            nDir = 1;
            nGap = getGap(nAutoMode, nGapBest);
            if (nGap < nGapBest) {
                nGapBest = nGap;
                nDirBest = 1;
            }
        }
        copy_board(board, board_bak);
        if (move_left() > 0) {
            nDir = 2;
            nGap = getGap(nAutoMode, nGapBest);
            if (nGap < nGapBest) {
                nGapBest = nGap;
                nDirBest = 2;
            }
        }
        copy_board(board, board_bak);
        if (move_down() > 0) {
            nDir = 3;
            nGap = getGap(nAutoMode, nGapBest);
            if (nGap < nGapBest) {
                nGapBest = nGap;
                nDirBest = 3;
            }
        }
        copy_board(board, board_bak);
        if (move_right() > 0) {
            nDir = 4;
            nGap = getGap(nAutoMode, nGapBest);
            if (nGap < nGapBest) {
                nGapBest = nGap;
                nDirBest = 4;
            }
        }
        copy_board(board, board_bak);
        sp--;
        if (move) {
            if (nDirBest == 0) {
                Console.Write("\n***** Give UP *****\n");
                nDirBest = nDir;
            }
            switch (nDirBest) {
            case 1:
                move_up();
                break;
            case 2:
                move_left();
                break;
            case 3:
                move_down();
                break;
            case 4:
                move_right();
                break;
            }
        }
        return nGapBest;
    }

    static double getGap(int nAutoMode, double nGapBest) {
        count_getGap++;
        double ret = 0.0;
        int nEmpty = 0;
        double nBonus = 0.0;
        bool movable = isMovable(ref nEmpty, ref nBonus);
        if (! movable) {
            ret = GAP_MAX;
        } else if (nAutoMode <= 1) {
            ret = getGap1(nGapBest, nEmpty, nBonus);
        } else {
            double alpha = nGapBest * (double)(nEmpty); //累積がこれを超えれば、平均してもnGapBestを超えるので即枝刈りする
            for (int x = 0; x < XMAX; x++) {
                for (int y = 0; y < YMAX; y++) {
                    if (isEmpty(x, y)) {
                        setCell(x, y, INIT2);
                        ret += moveBest(nAutoMode-1, false) * (RNDMAX - 1) / RNDMAX;
                        if (ret >= alpha) {
                            return GAP_MAX;	//枝刈り
                        }
                        setCell(x, y, INIT4);
                        ret += moveBest(nAutoMode-1, false) / RNDMAX;
                        if (ret >= alpha) {
                            return GAP_MAX;	//枝刈り
                        }
                        clearCell(x, y);
                    }
                }
            }
            ret /= (double)(nEmpty); //平均値を返す
        }
        return ret;
    }

    static double getGap1(double nGapBest, int nEmpty, double nBonus) {
        double ret = 0.0;
        double ret_appear = 0.0;
        double alpha = nGapBest * nBonus;
        bool edgea = false;
        bool edgeb = false;
        for (int x = 0; x < XMAX; x++) {
            for (int y = 0; y < YMAX; y++) {
                int v = getCell(x, y);
                edgea = (x == 0 || y == 0) || (x == XMAX - 1 || y == YMAX_1);
                if (v > 0) {
                    if (x < XMAX_1) {
                        int x1 = getCell(x+1, y);
                        edgeb = (y == 0) || (x+1 == XMAX - 1 || y == YMAX_1);
                        if (x1 > 0) {
                            ret += calcGap(v, x1, edgea, edgeb);
                        } else {
                            ret_appear += calcGap(v, INIT2, edgea, edgeb) * (RNDMAX - 1) / RNDMAX;
                            ret_appear += calcGap(v, INIT4, edgea, edgeb) / RNDMAX;
                        }
                    }
                    if (y < YMAX_1) {
                        int y1 = getCell(x, y+1);
                        edgeb = (x == 0) || (x == XMAX - 1 || y+1 == YMAX_1);
                        if (y1 > 0) {
                            ret += calcGap(v, y1, edgea, edgeb);
                        } else {
                            ret_appear += calcGap(v, INIT2, edgea, edgeb) * (RNDMAX - 1) / RNDMAX;
                            ret_appear += calcGap(v, INIT4, edgea, edgeb) / RNDMAX;
                        }
                    }
                } else {
                    if (x < XMAX_1) {
                        int x1 = getCell(x+1, y);
                        edgeb = (y == 0) || (x+1 == XMAX - 1 || y == YMAX_1);
                        if (x1 > 0) {
                            ret_appear += calcGap(INIT2, x1, edgea, edgeb) * (RNDMAX - 1) / RNDMAX;
                            ret_appear += calcGap(INIT4, x1, edgea, edgeb) / RNDMAX;
                        }
                    }
                    if (y < YMAX_1) {
                        int y1 = getCell(x, y+1);
                        edgeb = (x == 0) || (x == XMAX - 1 || y+1 == YMAX_1);
                        if (y1 > 0) {
                            ret_appear += calcGap(INIT2, y1, edgea, edgeb) * (RNDMAX - 1) / RNDMAX;
                            ret_appear += calcGap(INIT4, y1, edgea, edgeb) / RNDMAX;
                        }
                    }
                }
                if (ret + ret_appear/(double)(nEmpty) > alpha) {
                    return GAP_MAX;
                }
            }
        }
        ret += ret_appear / (double)(nEmpty);
        ret /= nBonus;
        return ret;
    }

    static double calcGap(int a, int b, bool edgea, bool edgeb) {
        count_calcGap++;
        double ret = 0;
        if (a > b) {
            ret = (double)(a - b);
            if (calc_gap_mode > 0 && ! edgea && edgeb) {
                switch (calc_gap_mode) {
                case 1:
                    ret += 1;
                    break;
                case 2:
                    ret *= 2;
                    break;
                case 3:
                    ret += (double)(a);
                    break;
                case 4:
                    ret += (double)(a)/10;
                    break;
                case 5:
                    ret += (double)(a+b);
                    break;
                }
            }
        } else if (a < b) {
            ret = (double)(b - a);
            if (calc_gap_mode > 0 && edgea && ! edgeb) {
                switch (calc_gap_mode) {
                case 1:
                    ret += 1;
                    break;
                case 2:
                    ret *= 2;
                    break;
                case 3:
                    ret += (double)(b);
                    break;
                case 4:
                    ret += (double)(b)/10;
                    break;
                case 5:
                    ret += (double)(a+b);
                    break;
                }
            }
        } else {
            ret = GAP_EQUAL;
        }
        return ret;
    }

    static bool isMovable(ref int ref_nEmpty, ref double ref_nBonus) {
        bool ret = false; //動けるか？
        int nEmpty = 0; //空きの数
        double nBonus = 1.0; //ボーナス（隅が最大値ならD_BONUS）
        int max_x = 0, max_y = 0;
        int max = 0;
        for (int y = 0; y < YMAX; y++) {
            for (int x = 0; x < XMAX; x++) {
                int val = getCell(x, y);
                if (val == 0) {
                    ret = true;
                    nEmpty++;
                } else {
                    if (val > max) {
                        max = val;
                        max_x = x;
                        max_y = y;
                    }
                    if (! ret) {
                        if (x < XMAX_1) {
                            int x1 = getCell(x+1, y);
                            if (val == x1 || x1 == 0) {
                                ret = true;
                            }
                        }
                        if (y < YMAX_1) {
                            int y1 = getCell(x, y+1);
                            if (val == y1 || y1 == 0) {
                                ret = true;
                            }
                        }
                    }
                }
            }
        }
        if ((max_x == 0 || max_x == XMAX_1) &&
            (max_y == 0 || max_y == YMAX_1)) {
            if (D_BONUS_USE_MAX) {
                nBonus = (double)(max);
            } else {
                nBonus = D_BONUS;
            }
        }
        ref_nEmpty = nEmpty;
        ref_nBonus = nBonus;
        return ret;
    }

    public static void Main()
    {
/*
        pauto_mode := flag.Int("level", auto_mode, "読みの深さ(>0)")
        pcalc_gap_mode := flag.Int("calc", calc_gap_mode, "gap計算モード(0:normal 1:端の方が小さければ+1 2:*2 3:+大きい方の値 4:+大きい方の値/10 5:+両方の値)")
        pprint_mode := flag.Int("print", print_mode, "途中経過の表示間隔(0：表示しない)")
        pprint_mode_turbo := flag.Int("print_mode_turbo", print_mode_turbo, "0:PRINT_MODEに従う 1:TURBO_MINUS_SCOREを超えたら強制表示 2:TURBO_PLUS_SCOREを超えたら強制表示")
        ppause_mode := flag.Int("pause", pause_mode, "終了時に一時中断(0/1)")
        pone_time := flag.Int("one_time", one_time, "N回で終了")
        pseed := flag.long("seed", seed, "乱数の種")
        pturbo_minus_percent := flag.Int("turbo_minus_percent", turbo_minus_percent, "turbo_minus_percent")
        pturbo_minus_percent_level := flag.Int("turbo_minus_percent_level", turbo_minus_percent_level, "turbo_minus_percent_level")
        pturbo_minus_score := flag.Int("turbo_minus_score", turbo_minus_score, "turbo_minus_score")
        pturbo_minus_score_level := flag.Int("turbo_minus_score_level", turbo_minus_score_level, "turbo_minus_score_level")
        pturbo_plus_percent := flag.Int("turbo_plus_percent", turbo_plus_percent, "turbo_plus_percent")
        pturbo_plus_percent_level := flag.Int("turbo_plus_percent_level", turbo_plus_percent_level, "turbo_plus_percent_level")
        pturbo_plus_score := flag.Int("turbo_plus_score", turbo_plus_score, "turbo_plus_score")
        pturbo_plus_score_level := flag.Int("turbo_plus_score_level", turbo_plus_score_level, "turbo_plus_score_level")
*/
        Console.WriteLine("auto_mode={0}", auto_mode);
        Console.WriteLine("calc_gap_mode={0}", calc_gap_mode);
        Console.WriteLine("print_mode={0}", print_mode);
        Console.WriteLine("print_mode_turbo={0}", print_mode_turbo);
        Console.WriteLine("pause_mode={0}", pause_mode);
        Console.WriteLine("seed={0}", seed);
        Console.WriteLine("one_time={0}", one_time);
        Console.WriteLine("turbo_minus_percent={0}", turbo_minus_percent);
        Console.WriteLine("turbo_minus_percent_level={0}", turbo_minus_percent_level);
        Console.WriteLine("turbo_minus_score={0}", turbo_minus_score);
        Console.WriteLine("turbo_minus_score_level={0}", turbo_minus_score_level);
        Console.WriteLine("turbo_plus_percent={0}", turbo_plus_percent);
        Console.WriteLine("turbo_plus_percent_level={0}", turbo_plus_percent_level);
        Console.WriteLine("turbo_plus_score={0}", turbo_plus_score);
        Console.WriteLine("turbo_plus_score_level={0}", turbo_plus_score_level);

        if (seed > 0) {
            rnd = new Random(seed);
        } else {
            rnd = new Random();
        }
        total_start_time = DateTime.Now.Ticks;
        init_game();
        while(true) {
            double gap = moveAuto(auto_mode);
            gen++;
            appear();
            disp(gap, print_mode > 0 &&
                (gen%print_mode==0 ||
                    (print_mode_turbo==1 && score>turbo_minus_score) ||
                    (print_mode_turbo==2 && score>turbo_plus_score)));
            if (isGameOver()) {
                int sc = getScore();
                sum_score += sc;
                if (sc > max_score) {
                    max_score = sc;
                    max_seed = seed;
                }
                if (sc < min_score) {
                    min_score = sc;
                    min_seed = seed;
                }
                Console.Write("Game Over! (level={0} seed={1}) {2} #{3} Ave.={4} Max={5}(seed={6}) Min={7}(seed={8})\ngetGap={9} calcGap={10} {11:f1},{12:f1} {13}%,{14} {15},{16} {17}%,{18} {19},{20} {21} calc_gap_mode={22}\n",
                    auto_mode, seed,
                    getTime(), count, sum_score/count,
                    max_score, max_seed, min_score, min_seed,
                    count_getGap, count_calcGap,
                    (double)(D_BONUS), (double)(GAP_EQUAL),
                    turbo_minus_percent, turbo_minus_percent_level,
                    turbo_minus_score, turbo_minus_score_level,
                    turbo_plus_percent, turbo_plus_percent_level,
                    turbo_plus_score, turbo_plus_score_level,
                    print_mode_turbo, calc_gap_mode);
                disp(gap, true);
                if (one_time > 0) {
                    one_time--;
                    if (one_time == 0) {
                        break;
                    }
                }
                if (pause_mode > 0) {
                    string key = Console.ReadLine();
                    if (key == "q") {
                        break;
                    }
                }
                seed++;
                rnd = new Random(seed);
                init_game();
                count++;
            }
        }
        total_last_time = DateTime.Now.Ticks;
        Console.Write("Total time = {0:f1} (sec)\n", (double)(total_last_time-total_start_time)/ticks_per_sec);
    }
}
