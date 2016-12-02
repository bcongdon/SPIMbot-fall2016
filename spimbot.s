# syscall constants
PRINT_STRING = 4
PRINT_CHAR   = 11
PRINT_INT    = 1

# debug constants
PRINT_INT_ADDR   = 0xffff0080
PRINT_FLOAT_ADDR = 0xffff0084
PRINT_HEX_ADDR   = 0xffff0088

# spimbot constants
VELOCITY       = 0xffff0010
ANGLE          = 0xffff0014
ANGLE_CONTROL  = 0xffff0018
BOT_X          = 0xffff0020
BOT_Y          = 0xffff0024
OTHER_BOT_X    = 0xffff00a0
OTHER_BOT_Y    = 0xffff00a4
TIMER          = 0xffff001c
SCORES_REQUEST = 0xffff1018

TILE_SCAN       = 0xffff0024
SEED_TILE       = 0xffff0054
WATER_TILE      = 0xffff002c
MAX_GROWTH_TILE = 0xffff0030
HARVEST_TILE    = 0xffff0020
BURN_TILE       = 0xffff0058
GET_FIRE_LOC    = 0xffff0028
PUT_OUT_FIRE    = 0xffff0040

GET_NUM_WATER_DROPS   = 0xffff0044
GET_NUM_SEEDS         = 0xffff0048
GET_NUM_FIRE_STARTERS = 0xffff004c
SET_RESOURCE_TYPE     = 0xffff00dc
REQUEST_PUZZLE        = 0xffff00d0
SUBMIT_SOLUTION       = 0xffff00d4

# interrupt constants
BONK_MASK               = 0x1000
BONK_ACK                = 0xffff0060
TIMER_MASK              = 0x8000
TIMER_ACK               = 0xffff006c
ON_FIRE_MASK            = 0x400
ON_FIRE_ACK             = 0xffff0050
MAX_GROWTH_ACK          = 0xffff005c
MAX_GROWTH_INT_MASK     = 0x2000
REQUEST_PUZZLE_ACK      = 0xffff00d8
REQUEST_PUZZLE_INT_MASK = 0x800

.data
# data things go here
three:  .float  3.0
five:   .float  5.0
PI:     .float  3.141592
F180:   .float  180.0

.align 2
tile_data:      .space 1600
puzzle:         .space 4096
solution:       .space 328

.text
main:
	# go wild
	# the world is your oyster :)
        jal     zero_sol
        li      $a0, 0
        li      $a1, 0
        jal     goto_loc
        li      $a0, 8
        li      $a1, 0
        jal     goto_loc
        li      $a0, 5
        li      $a1, 5
        jal     goto_loc
        li      $a0, 9
        li      $a1, 9
        jal     goto_loc
loop:
	j	loop


# -----------------------------------------------------------------------
# goto_loc - goes to grid coordinate x, y in direct path
# $a0 - x
# $a1 - y
# returns when at target
# -----------------------------------------------------------------------
goto_loc:
        # calculate dx and dy
        sub     $sp, $sp, 12
        sw      $ra, 0($sp)
        sw      $s0, 4($sp)
        sw      $s1, 8($sp)

        # Convert from graph coords to world coords
        mul     $a0, $a0, 30
        add     $a0, $a0, 15
        mul     $a1, $a1, 30
        add     $a1, $a1, 15

        move    $s0, $a0
        move    $s1, $a1

        lw      $t0, BOT_X
        sub     $a0, $a0, $t0
        lw      $t1, BOT_Y
        sub     $a1, $a1, $t1
        # find angle from current location to target
        jal     sb_arctan
        # set angle towards target
        sw      $v0, ANGLE
        li      $t0, 1
        sw      $t0, ANGLE_CONTROL
        li      $t0, 10
        sw      $t0, VELOCITY
goto_loc_loop:
        lw      $t0, BOT_X
        lw      $t1, BOT_Y
        sub     $a0, $t0, $s0
        sub     $a1, $t1, $s1
        jal     euclidean_dist
        li      $t0, 10
        bgt     $v0, $t0, goto_loc_loop
goto_loc_done:
        sw      $0, VELOCITY
        lw      $ra, 0($sp)
        lw      $s0, 4($sp)
        lw      $s1, 8($sp)
        add     $sp, $sp, 12
        jr      $ra

# -----------------------------------------------------------------------
# zero_sol - zeros out the solution data space
# -----------------------------------------------------------------------
zero_sol:
        la      $t0, solution
        li      $t1, 328
        add     $t1, $t1, $t0           # Final Address
zero_sol_loop:
        bge     $t0, $t1, zero_sol_done
        sw      $0, 0($t0)
        add     $t0, $t0, 4
        j       zero_sol_loop
zero_sol_done:
        jr      $ra


# -----------------------------------------------------------------------
# sb_arctan - computes the arctangent of y / x
# $a0 - x
# $a1 - y
# returns the arctangent
# -----------------------------------------------------------------------

sb_arctan:
        li      $v0, 0          # angle = 0;

        abs     $t0, $a0        # get absolute values
        abs     $t1, $a1
        ble     $t1, $t0, no_TURN_90      

        ## if (abs(y) > abs(x)) { rotate 90 degrees }
        move    $t0, $a1        # int temp = y;
        neg     $a1, $a0        # y = -x;      
        move    $a0, $t0        # x = temp;    
        li      $v0, 90         # angle = 90;  

no_TURN_90:
        bgez    $a0, pos_x      # skip if (x >= 0)

        ## if (x < 0) 
        add     $v0, $v0, 180   # angle += 180;

pos_x:
        mtc1    $a0, $f0
        mtc1    $a1, $f1
        cvt.s.w $f0, $f0        # convert from ints to floats
        cvt.s.w $f1, $f1
        
        div.s   $f0, $f1, $f0   # float v = (float) y / (float) x;

        mul.s   $f1, $f0, $f0   # v^^2
        mul.s   $f2, $f1, $f0   # v^^3
        l.s     $f3, three      # load 5.0
        div.s   $f3, $f2, $f3   # v^^3/3
        sub.s   $f6, $f0, $f3   # v - v^^3/3

        mul.s   $f4, $f1, $f2   # v^^5
        l.s     $f5, five       # load 3.0
        div.s   $f5, $f4, $f5   # v^^5/5
        add.s   $f6, $f6, $f5   # value = v - v^^3/3 + v^^5/5

        l.s     $f8, PI         # load PI
        div.s   $f6, $f6, $f8   # value / PI
        l.s     $f7, F180       # load 180.0
        mul.s   $f6, $f6, $f7   # 180.0 * value / PI

        cvt.w.s $f6, $f6        # convert "delta" back to integer
        mfc1    $t0, $f6
        add     $v0, $v0, $t0   # angle += delta

        jr      $ra

# -----------------------------------------------------------------------
# euclidean_dist - computes sqrt(x^2 + y^2)
# $a0 - x
# $a1 - y
# returns the distance
# -----------------------------------------------------------------------

euclidean_dist:
        mul     $a0, $a0, $a0   # x^2
        mul     $a1, $a1, $a1   # y^2
        add     $v0, $a0, $a1   # x^2 + y^2
        mtc1    $v0, $f0
        cvt.s.w $f0, $f0        # float(x^2 + y^2)
        sqrt.s  $f0, $f0        # sqrt(x^2 + y^2)
        cvt.w.s $f0, $f0        # int(sqrt(...))
        mfc1    $v0, $f0
        jr      $ra