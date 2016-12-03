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

# logic constants
DESIRED_NUM_PLANTS = 5
DESIRED_NUM_SEEDS  = 3
DESIRED_NUM_WATER  = 30
DESIRED_NUM_FIRE_STARTERS = 1

.data
# data things go here
.align 4
three:  .float  3.0
five:   .float  5.0
PI:     .float  3.141592
F180:   .float  180.0

.align 4
puzzle_available_flag:  .word   0
puzzle_requested_flag:  .word   0
moving:                 .word   0

.align 4
tile_data:              .space 1600
puzzle_data:            .space 4096
solution_data:          .space 328

fire_queue:          .space 4000
fire_q_begin:        .word  0
fire_q_end:          .word  0

max_growth_queue:       .space 4000
max_growth_q_begin:     .word  0
max_growth_q_end:       .word  0

.text
main:
        # stop initial velocity
        sw      $0, VELOCITY

        # setup data queues
        la      $t0, fire_queue
        sw      $t0, fire_q_begin
        sw      $t0, fire_q_end

        la      $t0, max_growth_queue
        sw      $t0, max_growth_q_begin
        sw      $t0, max_growth_q_end

        # setup interrupts
        li      $t0, REQUEST_PUZZLE_INT_MASK
        or      $t0, $t0, TIMER_MASK
        or      $t0, $t0, MAX_GROWTH_INT_MASK
        or      $t0, $t0, ON_FIRE_MASK
        or      $t0, $t0, 1
        mtc0    $t0, $12

        # immediately request a puzzle
        jal     request_puzzle

main_logic_loop:
        # Do a tile scan
        la      $t0, tile_data
        sw      $t0, TILE_SCAN
        # Check if any tiles burning
        lw      $t0, fire_q_end
        lw      $t1, fire_q_begin
        beq     $t0, $t1, no_tiles_burning                      # Skip firefighting if unnecessary
        # handle burning tile
        jal     put_out_first_fire
no_tiles_burning:
        # Check if any tiles max_growth
        lw      $t0, max_growth_q_end
        lw      $t1, max_growth_q_begin
        beq     $t0, $t1, no_tiles_max_growth
        # handle max growth tiles
        # TODO
no_tiles_max_growth:
        # Check if should plant more
        jal     count_plants
        bge     $v0, DESIRED_NUM_PLANTS, plant_needs_satisfied  # Skip planting if happy with num of plants
        # handle planting more plants
        jal     plant_a_new_location
plant_needs_satisfied:
        # Check if can burn enemy tiles
        jal     get_enemy_tile
        beq     $v0, 0xffffffff, burning_needs_satisfied        # Skip burning if no tiles available
burning_needs_satisfied:
        jal     get_resource
        j       main_logic_loop

        # Random test movement
        la      $t0, puzzle_data
        sw      $t0, REQUEST_PUZZLE
        jal     solve_puzzle
        
        
        jal     zero_sol
        
        jal     wait_until_at_dest
        li      $a0, 8
        li      $a1, 0
        jal     goto_loc
        jal     wait_until_at_dest
        li      $a0, 5
        li      $a1, 5
        jal     goto_loc
        jal     wait_until_at_dest
        li      $a0, 9
        li      $a1, 9
        jal     goto_loc
        j       main_logic_loop

# -----------------------------------------------------------------------
# get_resource - get the number of currently owned plants
# $a0 - specific resource to get (0, 1, or 2)
#     - if set to 0xffffffff, will get resource most needed by priority
#     - if all needs satisfied, will return without doing a puzzle
# -----------------------------------------------------------------------
# $t1 - used to eventually specify resource
# -----------------------------------------------------------------------
get_resource:
        beq     $a0, 0xffffffff, gr_pick_resource         # if resource unspecified, do priority picking
        move    $t1, $a0
        j       gr_do_puzzle
gr_pick_resource:
        lw      $t0, GET_NUM_WATER_DROPS
        bge     $t0, DESIRED_NUM_WATER, gr_not_water
        li      $t1, 0
        j       gr_do_puzzle
gr_not_water:
        lw      $t0, GET_NUM_SEEDS
        bge     $t0, DESIRED_NUM_SEEDS, gr_not_seeds
        li      $t1, 1 
        j       gr_do_puzzle
gr_not_seeds:
        lw      $t0, GET_NUM_FIRE_STARTERS
        bge     $t0, DESIRED_NUM_FIRE_STARTERS, gr_no_resources_needed
        li      $t1, 2
        j       gr_do_puzzle
gr_no_resources_needed:
        jr      $ra
gr_do_puzzle:
        sw      $t1, SET_RESOURCE_TYPE
        sub     $sp, $sp, 4
        sw      $ra, 0($sp)
        jal     solve_puzzle
        lw      $ra, 0($sp)
        add     $sp, $sp, 4
        jr      $ra

# -----------------------------------------------------------------------
# put_out_first_fire - puts out first fire in queue
# -----------------------------------------------------------------------
put_out_first_fire:
        sub     $sp, $sp, 4
        sw      $ra, 0($sp)

        # get first fire location
        lw      $t0, fire_q_begin
        add     $t0, $t0, 4
        sw      $t0, fire_q_begin       # increment fire queue begin pointer
        lw      $t0, 0($t0)             # t0 = fire location
        and     $a0, $t0, 0xffff        # a0 = x
        srl     $a1, $t0, 16            # a1 = y

        # check to see tile is owned by us
        # calculate index to tile
        mul     $t1, $a1, 10
        add     $t1, $t1, $a0           # t1 = tile offset
        # Do tile scan
        la      $t2, tile_data
        sw      $t2, TILE_SCAN          # request a tile scan
        # lookup owner of fire tile
        mul     $t3, $t1, 32            # offset to tiles[tile_index]
        add     $t3, $t3, $t2           # &tiles[tile_index]
        lw      $t3, 4($t3)             # t3 = tiles[tile_index].owning_bot
        # bail if we don't done the on-fire tile
        bne     $t3, 0, poff_done

        # proceed to put out fire
        jal     goto_loc                # start moving to fire location
        li      $a0, 0                  # resource to get is water
        jal     get_resource
        jal     wait_until_at_dest
        sw      $0, PUT_OUT_FIRE        # put out fire at location

poff_done:
        lw      $ra, 0($sp)
        add     $sp, $sp, 4        
        jr      $ra

# -----------------------------------------------------------------------
# plant_a_new_location - selects location and plants a seed
# -----------------------------------------------------------------------
plant_a_new_location:
        sub     $sp, $sp, 4
        sw      $ra, 0($sp)

        lw      $t0, TIMER
        div     $a0, $t0, 7
        rem     $a0, $a0, 10
        rem     $a1, $t0, 10

        jal     goto_loc
        la      $a0, 1
        jal     get_resource            # get a seed on the way
        la      $a0, 0
        jal     get_resource            # get water too
        jal     wait_until_at_dest
        sw      $0, SEED_TILE
        li      $t0, 10
        sw      $t0, WATER_TILE         # water new plant
        lw      $ra, 0($sp)
        add     $sp, $sp, 4
        jr      $ra


# -----------------------------------------------------------------------
# count_plants - get the number of currently owned plants
# returns number of plants
# -----------------------------------------------------------------------
count_plants:
        # Do tile scan
        la      $t2, tile_data
        sw      $t2, TILE_SCAN          # request a tile scan
        add     $t1, $t2, 1600          # final address
        li      $t7, 0                  # t7 = plant_count
cp_loop:
        bge     $t2, $t1, cp_done
        lw      $t3, 0($t2)                     # tiles[tile_index].state
        bne     $t3, 1, cp_loop_continue        # skip if not growing
        lw      $t3, 4($t2)                     # tiles[tile_index].owning_bot
        bne     $t3, 0, cp_loop_continue        # skip it not owned by us
        add     $t7, $t7, 1                     # plant_count ++
        j       cp_loop_continue
cp_loop_continue:
        add     $t2, $t2, 32            # increment pointer
        j       cp_loop
cp_done:
        move    $v0, $t7                # return plant_count
        jr      $ra

# -----------------------------------------------------------------------
# get_enemy_tile - gets the closest enemy tile to burn
# returns closest enemy tile, 0xffffffff if no tiles to burn
# -----------------------------------------------------------------------
get_enemy_tile:
        # TODO
        li      $v0, 0xffffffff
        jr      $ra

# -----------------------------------------------------------------------
# request_puzzle - requests a puzzle
# be careful not to request a new puzzle before solving old one
# -----------------------------------------------------------------------
request_puzzle:
        lw      $t0, puzzle_requested_flag
        bne     $t0, $0, rp_done                # skip request if a puzzle has already been requested
        la      $t0, puzzle_data
        sw      $t0, REQUEST_PUZZLE
        li      $t1, 1
        sw      $t1, puzzle_requested_flag
rp_done:
        jr      $ra

# -----------------------------------------------------------------------
# solve_puzzle - synchronously solves 1 puzzle (doesn't return until
#                puzzle is solved)
#              - requests puzzle if not already done so
#              - submits puzzle once done 
#              - zeros out solution once done
# -----------------------------------------------------------------------
solve_puzzle:
        lw      $t0, puzzle_requested_flag
        bne     $t0, 0, sp_already_requested
        # Request puzzle if necessary
        sub     $sp, $sp, 4
        sw      $ra, 0($sp)
        jal     request_puzzle
        lw      $ra, 0($sp)
        add     $sp, $sp, 4
sp_already_requested:
        la      $t0, puzzle_available_flag
        sub     $sp, $sp, 4
        sw      $ra, 0($sp)
puzzle_wait:
        lw      $t1, 0($t0)
        bne     $t1, 0, puzzle_ready
        j       puzzle_wait
puzzle_ready:
        la      $a0, solution_data
        la      $a1, puzzle_data
        jal     recursive_backtracking
        sw      $0, puzzle_available_flag       # puzzle_available_flag = 0
        sw      $0, puzzle_requested_flag       # puzzle_requested_flag = 0
        la      $a0, solution_data
        sw      $a0, SUBMIT_SOLUTION            # submit solution
        jal     zero_sol                        # zero out solution
        jal     request_puzzle                  # immediately requst another puzzle
        lw      $ra, 0($sp)
        add     $sp, $sp, 4
        jr      $ra


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
        sw      $s0, 4($sp)             # target worldx
        sw      $s1, 8($sp)             # target worldy

        # Convert from graph coords to world coords
        mul     $a0, $a0, 30
        add     $a0, $a0, 15            # worldx = 30*x + 15
        mul     $a1, $a1, 30
        add     $a1, $a1, 15            # worldy = 30*y + 15

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
        # set positive velocity
        li      $t0, 10
        sw      $t0, VELOCITY
        # set movement flag to true
        la      $t3, moving
        li      $t4, 1
        sw      $t4, 0($t3)             # moving = 1

        # calculate dist to destination
        lw      $t0, BOT_X
        sub     $a0, $s0, $t0
        lw      $t1, BOT_Y
        sub     $a1, $s1, $t1
        jal     euclidean_dist
        # calculate time to destination
        lw      $t0, TIMER
        mul     $t1, $v0, 1000  # at velocity = 10, speed is 1000 cycles / distance unit
        add     $t1, $t1, $t0
        sw      $t1, TIMER      # set timer interupt for when we will arrive

        # clean up
        lw      $ra, 0($sp)
        lw      $s0, 4($sp)
        lw      $s1, 8($sp)
        add     $sp, $sp, 12
        jr      $ra

# -----------------------------------------------------------------------
# wait_until_at_dest - causes spimbot to wait until it has stopped moving
# -----------------------------------------------------------------------
wait_until_at_dest:
        la      $t0, moving
wait_until_dest_loop:
        lw      $t1, 0($t0)
        beq     $t1, 0, wait_until_dest_done
        j       wait_until_at_dest
wait_until_dest_done:
        jr      $ra

# -----------------------------------------------------------------------
# zero_sol - zeros out the solution data space
# -----------------------------------------------------------------------
zero_sol:
        la      $t0, solution_data
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


# -----------------------------------------------------------------------
# puzzle solving code:
# -----------------------------------------------------------------------

recursive_backtracking:
  sub   $sp, $sp, 680
  sw    $ra, 0($sp)
  sw    $a0, 4($sp)     # solution
  sw    $a1, 8($sp)     # puzzle
  sw    $s0, 12($sp)    # position
  sw    $s1, 16($sp)    # val
  sw    $s2, 20($sp)    # 0x1 << (val - 1)
                        # sizeof(Puzzle) = 8
                        # sizeof(Cell [81]) = 648

  jal   is_complete
  bne   $v0, $0, recursive_backtracking_return_one
  lw    $a0, 4($sp)     # solution
  lw    $a1, 8($sp)     # puzzle
  jal   get_unassigned_position
  move  $s0, $v0        # position
  li    $s1, 1          # val = 1
recursive_backtracking_for_loop:
  lw    $a0, 4($sp)     # solution
  lw    $a1, 8($sp)     # puzzle
  lw    $t0, 0($a1)     # puzzle->size
  add   $t1, $t0, 1     # puzzle->size + 1
  bge   $s1, $t1, recursive_backtracking_return_zero  # val < puzzle->size + 1
  lw    $t1, 4($a1)     # puzzle->grid
  mul   $t4, $s0, 8     # sizeof(Cell) = 8
  add   $t1, $t1, $t4   # &puzzle->grid[position]
  lw    $t1, 0($t1)     # puzzle->grid[position].domain
  sub   $t4, $s1, 1     # val - 1
  li    $t5, 1
  sll   $s2, $t5, $t4   # 0x1 << (val - 1)
  and   $t1, $t1, $s2   # puzzle->grid[position].domain & (0x1 << (val - 1))
  beq   $t1, $0, recursive_backtracking_for_loop_continue # if (domain & (0x1 << (val - 1)))
  mul   $t0, $s0, 4     # position * 4
  add   $t0, $t0, $a0
  add   $t0, $t0, 4     # &solution->assignment[position]
  sw    $s1, 0($t0)     # solution->assignment[position] = val
  lw    $t0, 0($a0)     # solution->size
  add   $t0, $t0, 1
  sw    $t0, 0($a0)     # solution->size++
  add   $t0, $sp, 32    # &grid_copy
  sw    $t0, 28($sp)    # puzzle_copy.grid = grid_copy !!!
  move  $a0, $a1        # &puzzle
  add   $a1, $sp, 24    # &puzzle_copy
  jal   clone           # clone(puzzle, &puzzle_copy)
  mul   $t0, $s0, 8     # !!! grid size 8
  lw    $t1, 28($sp)
  
  add   $t1, $t1, $t0   # &puzzle_copy.grid[position]
  sw    $s2, 0($t1)     # puzzle_copy.grid[position].domain = 0x1 << (val - 1);
  move  $a0, $s0
  add   $a1, $sp, 24
  jal   forward_checking  # forward_checking(position, &puzzle_copy)
  beq   $v0, $0, recursive_backtracking_skip

  lw    $a0, 4($sp)     # solution
  add   $a1, $sp, 24    # &puzzle_copy
  jal   recursive_backtracking
  beq   $v0, $0, recursive_backtracking_skip
  j     recursive_backtracking_return_one # if (recursive_backtracking(solution, &puzzle_copy))
recursive_backtracking_skip:
  lw    $a0, 4($sp)     # solution
  mul   $t0, $s0, 4
  add   $t1, $a0, 4
  add   $t1, $t1, $t0
  sw    $0, 0($t1)      # solution->assignment[position] = 0
  lw    $t0, 0($a0)
  sub   $t0, $t0, 1
  sw    $t0, 0($a0)     # solution->size -= 1
recursive_backtracking_for_loop_continue:
  add   $s1, $s1, 1     # val++
  j     recursive_backtracking_for_loop
recursive_backtracking_return_zero:
  li    $v0, 0
  j     recursive_backtracking_return
recursive_backtracking_return_one:
  li    $v0, 1
recursive_backtracking_return:
  lw    $ra, 0($sp)
  lw    $a0, 4($sp)
  lw    $a1, 8($sp)
  lw    $s0, 12($sp)
  lw    $s1, 16($sp)
  lw    $s2, 20($sp)
  add   $sp, $sp, 680
  jr    $ra

forward_checking:
  sub   $sp, $sp, 24
  sw    $ra, 0($sp)
  sw    $a0, 4($sp)
  sw    $a1, 8($sp)
  sw    $s0, 12($sp)
  sw    $s1, 16($sp)
  sw    $s2, 20($sp)
  lw    $t0, 0($a1)     # size
  li    $t1, 0          # col = 0
fc_for_col:
  bge   $t1, $t0, fc_end_for_col  # col < size
  div   $a0, $t0
  mfhi  $t2             # position % size
  mflo  $t3             # position / size
  beq   $t1, $t2, fc_for_col_continue    # if (col != position % size)
  mul   $t4, $t3, $t0
  add   $t4, $t4, $t1   # position / size * size + col
  mul   $t4, $t4, 8
  lw    $t5, 4($a1) # puzzle->grid
  add   $t4, $t4, $t5   # &puzzle->grid[position / size * size + col].domain
  mul   $t2, $a0, 8   # position * 8
  add   $t2, $t5, $t2 # puzzle->grid[position]
  lw    $t2, 0($t2) # puzzle -> grid[position].domain
  not   $t2, $t2        # ~puzzle->grid[position].domain
  lw    $t3, 0($t4) #
  and   $t3, $t3, $t2
  sw    $t3, 0($t4)
  beq   $t3, $0, fc_return_zero # if (!puzzle->grid[position / size * size + col].domain)
fc_for_col_continue:
  add   $t1, $t1, 1     # col++
  j     fc_for_col
fc_end_for_col:
  li    $t1, 0          # row = 0
fc_for_row:
  bge   $t1, $t0, fc_end_for_row  # row < size
  div   $a0, $t0
  mflo  $t2             # position / size
  mfhi  $t3             # position % size
  beq   $t1, $t2, fc_for_row_continue
  lw    $t2, 4($a1)     # puzzle->grid
  mul   $t4, $t1, $t0
  add   $t4, $t4, $t3
  mul   $t4, $t4, 8
  add   $t4, $t2, $t4   # &puzzle->grid[row * size + position % size]
  lw    $t6, 0($t4)
  mul   $t5, $a0, 8
  add   $t5, $t2, $t5
  lw    $t5, 0($t5)     # puzzle->grid[position].domain
  not   $t5, $t5
  and   $t5, $t6, $t5
  sw    $t5, 0($t4)
  beq   $t5, $0, fc_return_zero
fc_for_row_continue:
  add   $t1, $t1, 1     # row++
  j     fc_for_row
fc_end_for_row:

  li    $s0, 0          # i = 0
fc_for_i:
  lw    $t2, 4($a1)
  mul   $t3, $a0, 8
  add   $t2, $t2, $t3
  lw    $t2, 4($t2)     # &puzzle->grid[position].cage
  lw    $t3, 8($t2)     # puzzle->grid[position].cage->num_cell
  bge   $s0, $t3, fc_return_one
  lw    $t3, 12($t2)    # puzzle->grid[position].cage->positions
  mul   $s1, $s0, 4
  add   $t3, $t3, $s1
  lw    $t3, 0($t3)     # pos
  lw    $s1, 4($a1)
  mul   $s2, $t3, 8
  add   $s2, $s1, $s2   # &puzzle->grid[pos].domain
  lw    $s1, 0($s2)
  move  $a0, $t3
  jal get_domain_for_cell
  lw    $a0, 4($sp)
  lw    $a1, 8($sp)
  and   $s1, $s1, $v0
  sw    $s1, 0($s2)     # puzzle->grid[pos].domain &= get_domain_for_cell(pos, puzzle)
  beq   $s1, $0, fc_return_zero
fc_for_i_continue:
  add   $s0, $s0, 1     # i++
  j     fc_for_i
fc_return_one:
  li    $v0, 1
  j     fc_return
fc_return_zero:
  li    $v0, 0
fc_return:
  lw    $ra, 0($sp)
  lw    $a0, 4($sp)
  lw    $a1, 8($sp)
  lw    $s0, 12($sp)
  lw    $s1, 16($sp)
  lw    $s2, 20($sp)
  add   $sp, $sp, 24
  jr    $ra

get_unassigned_position:
  li    $v0, 0            # unassigned_pos = 0
  lw    $t0, 0($a1)       # puzzle->size
  mul  $t0, $t0, $t0     # puzzle->size * puzzle->size
  add   $t1, $a0, 4       # &solution->assignment[0]
get_unassigned_position_for_begin:
  bge   $v0, $t0, get_unassigned_position_return  # if (unassigned_pos < puzzle->size * puzzle->size)
  mul  $t2, $v0, 4
  add   $t2, $t1, $t2     # &solution->assignment[unassigned_pos]
  lw    $t2, 0($t2)       # solution->assignment[unassigned_pos]
  beq   $t2, 0, get_unassigned_position_return  # if (solution->assignment[unassigned_pos] == 0)
  add   $v0, $v0, 1       # unassigned_pos++
  j   get_unassigned_position_for_begin
get_unassigned_position_return:
  jr    $ra

is_complete:
  lw    $t0, 0($a0)       # solution->size
  lw    $t1, 0($a1)       # puzzle->size
  mul   $t1, $t1, $t1     # puzzle->size * puzzle->size
  move  $v0, $0
  seq   $v0, $t0, $t1
  j     $ra

convert_highest_bit_to_int:
    move  $v0, $0             # result = 0

chbti_loop:
    beq   $a0, $0, chbti_end
    add   $v0, $v0, 1         # result ++
    sra   $a0, $a0, 1         # domain >>= 1
    j     chbti_loop

chbti_end:
    jr    $ra

.globl is_single_value_domain
is_single_value_domain:
    beq    $a0, $0, isvd_zero     # return 0 if domain == 0
    sub    $t0, $a0, 1            # (domain - 1)
    and    $t0, $t0, $a0          # (domain & (domain - 1))
    bne    $t0, $0, isvd_zero     # return 0 if (domain & (domain - 1)) != 0
    li     $v0, 1
    jr     $ra

isvd_zero:         
    li     $v0, 0
    jr     $ra

clone:

    lw  $t0, 0($a0)
    sw  $t0, 0($a1)

    mul $t0, $t0, $t0
    mul $t0, $t0, 2 # two words in one grid

    lw  $t1, 4($a0) # &puzzle(ori).grid
    lw  $t2, 4($a1) # &puzzle(clone).grid

    li  $t3, 0 # i = 0;
clone_for_loop:
    bge  $t3, $t0, clone_for_loop_end
    sll $t4, $t3, 2 # i * 4
    add $t5, $t1, $t4 # puzzle(ori).grid ith word
    lw   $t6, 0($t5)

    add $t5, $t2, $t4 # puzzle(clone).grid ith word
    sw   $t6, 0($t5)
    
    addi $t3, $t3, 1 # i++
    
    j    clone_for_loop
clone_for_loop_end:

    jr  $ra

get_domain_for_cell:
    # save registers    
    sub $sp, $sp, 36
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)
    sw $s4, 20($sp)
    sw $s5, 24($sp)
    sw $s6, 28($sp)
    sw $s7, 32($sp)

    li $t0, 0 # valid_domain
    lw $t1, 4($a1) # puzzle->grid (t1 free)
    sll $t2, $a0, 3 # position*8 (actual offset) (t2 free)
    add $t3, $t1, $t2 # &puzzle->grid[position]
    lw  $t4, 4($t3) # &puzzle->grid[position].cage
    lw  $t5, 0($t4) # puzzle->grid[posiition].cage->operation

    lw $t2, 4($t4) # puzzle->grid[position].cage->target

    move $s0, $t2   # remain_target = $s0  *!*!
    lw $s1, 8($t4) # remain_cell = $s1 = puzzle->grid[position].cage->num_cell
    lw $s2, 0($t3) # domain_union = $s2 = puzzle->grid[position].domain
    move $s3, $t4 # puzzle->grid[position].cage
    li $s4, 0   # i = 0
    move $s5, $t1 # $s5 = puzzle->grid
    move $s6, $a0 # $s6 = position
    # move $s7, $s2 # $s7 = puzzle->grid[position].domain

    bne $t5, 0, gdfc_check_else_if

    li $t1, 1
    sub $t2, $t2, $t1 # (puzzle->grid[position].cage->target-1)
    sll $v0, $t1, $t2 # valid_domain = 0x1 << (prev line comment)
    j gdfc_end # somewhere!!!!!!!!

gdfc_check_else_if:
    bne $t5, '+', gdfc_check_else

gdfc_else_if_loop:
    lw $t5, 8($s3) # puzzle->grid[position].cage->num_cell
    bge $s4, $t5, gdfc_for_end # branch if i >= puzzle->grid[position].cage->num_cell
    sll $t1, $s4, 2 # i*4
    lw $t6, 12($s3) # puzzle->grid[position].cage->positions
    add $t1, $t6, $t1 # &puzzle->grid[position].cage->positions[i]
    lw $t1, 0($t1) # pos = puzzle->grid[position].cage->positions[i]
    add $s4, $s4, 1 # i++

    sll $t2, $t1, 3 # pos * 8
    add $s7, $s5, $t2 # &puzzle->grid[pos]
    lw  $s7, 0($s7) # puzzle->grid[pos].domain

    beq $t1, $s6 gdfc_else_if_else # branch if pos == position

    

    move $a0, $s7 # $a0 = puzzle->grid[pos].domain
    jal is_single_value_domain
    bne $v0, 1 gdfc_else_if_else # branch if !is_single_value_domain()
    move $a0, $s7
    jal convert_highest_bit_to_int
    sub $s0, $s0, $v0 # remain_target -= convert_highest_bit_to_int
    addi $s1, $s1, -1 # remain_cell -= 1
    j gdfc_else_if_loop
gdfc_else_if_else:
    or $s2, $s2, $s7 # domain_union |= puzzle->grid[pos].domain
    j gdfc_else_if_loop

gdfc_for_end:
    move $a0, $s0
    move $a1, $s1
    move $a2, $s2
    jal get_domain_for_addition # $v0 = valid_domain = get_domain_for_addition()
    j gdfc_end

gdfc_check_else:
    lw $t3, 12($s3) # puzzle->grid[position].cage->positions
    lw $t0, 0($t3) # puzzle->grid[position].cage->positions[0]
    lw $t1, 4($t3) # puzzle->grid[position].cage->positions[1]
    xor $t0, $t0, $t1
    xor $t0, $t0, $s6 # other_pos = $t0 = $t0 ^ position
    lw $a0, 4($s3) # puzzle->grid[position].cage->target

    sll $t2, $s6, 3 # position * 8
    add $a1, $s5, $t2 # &puzzle->grid[position]
    lw  $a1, 0($a1) # puzzle->grid[position].domain
    # move $a1, $s7 

    sll $t1, $t0, 3 # other_pos*8 (actual offset)
    add $t3, $s5, $t1 # &puzzle->grid[other_pos]
    lw $a2, 0($t3)  # puzzle->grid[other_pos].domian

    jal get_domain_for_subtraction # $v0 = valid_domain = get_domain_for_subtraction()
    # j gdfc_end
gdfc_end:
# restore registers
    
    lw $ra, 0($sp)
    lw $s0, 4($sp)
    lw $s1, 8($sp)
    lw $s2, 12($sp)
    lw $s3, 16($sp)
    lw $s4, 20($sp)
    lw $s5, 24($sp)
    lw $s6, 28($sp)
    lw $s7, 32($sp)
    add $sp, $sp, 36    
    jr $ra

get_domain_for_addition:
    sub    $sp, $sp, 20
    sw     $ra, 0($sp)
    sw     $s0, 4($sp)
    sw     $s1, 8($sp)
    sw     $s2, 12($sp)
    sw     $s3, 16($sp)
    move   $s0, $a0                     # s0 = target
    move   $s1, $a1                     # s1 = num_cell
    move   $s2, $a2                     # s2 = domain

    move   $a0, $a2
    jal    convert_highest_bit_to_int
    move   $s3, $v0                     # s3 = upper_bound

    sub    $a0, $0, $s2                 # -domain
    and    $a0, $a0, $s2                # domain & (-domain)
    jal    convert_highest_bit_to_int   # v0 = lower_bound
           
    sub    $t0, $s1, 1                  # num_cell - 1
    mul    $t0, $t0, $v0                # (num_cell - 1) * lower_bound
    sub    $t0, $s0, $t0                # t0 = high_bits
    bge    $t0, 0, gdfa_skip0

    li     $t0, 0

gdfa_skip0:
    bge    $t0, $s3, gdfa_skip1

    li     $t1, 1          
    sll    $t0, $t1, $t0                # 1 << high_bits
    sub    $t0, $t0, 1                  # (1 << high_bits) - 1
    and    $s2, $s2, $t0                # domain & ((1 << high_bits) - 1)

gdfa_skip1:        
    sub    $t0, $s1, 1                  # num_cell - 1
    mul    $t0, $t0, $s3                # (num_cell - 1) * upper_bound
    sub    $t0, $s0, $t0                # t0 = low_bits
    ble    $t0, $0, gdfa_skip2

    sub    $t0, $t0, 1                  # low_bits - 1
    sra    $s2, $s2, $t0                # domain >> (low_bits - 1)
    sll    $s2, $s2, $t0                # domain >> (low_bits - 1) << (low_bits - 1)

gdfa_skip2:        
    move   $v0, $s2                     # return domain
    lw     $ra, 0($sp)
    lw     $s0, 4($sp)
    lw     $s1, 8($sp)
    lw     $s2, 12($sp)
    lw     $s3, 16($sp)
    add    $sp, $sp, 20
    jr     $ra

get_domain_for_subtraction:
    li     $t0, 1              
    li     $t1, 2
    mul    $t1, $t1, $a0            # target * 2
    sll    $t1, $t0, $t1            # 1 << (target * 2)
    or     $t0, $t0, $t1            # t0 = base_mask
    li     $t1, 0                   # t1 = mask

gdfs_loop:
    beq    $a2, $0, gdfs_loop_end       
    and    $t2, $a2, 1              # other_domain & 1
    beq    $t2, $0, gdfs_if_end
           
    sra    $t2, $t0, $a0            # base_mask >> target
    or     $t1, $t1, $t2            # mask |= (base_mask >> target)

gdfs_if_end:
    sll    $t0, $t0, 1              # base_mask <<= 1
    sra    $a2, $a2, 1              # other_domain >>= 1
    j      gdfs_loop

gdfs_loop_end:
    and    $v0, $a1, $t1            # domain & mask
    jr     $ra

.kdata
.align 4
chunkIH:        .space 12           # space for 3 registers

.ktext 0x80000180
interrupt_handler:
.set noat
        move    $k1, $at
.set at
        la      $k0, chunkIH
        sw      $a0, 0($k0)
        sw      $a1, 4($k0)
        sw      $a1, 8($k0)

interrupt_dispatch:
        mfc0    $k0, $13
        beq     $k0, 0, done

        and     $a0, $k0, TIMER_MASK                    # Is there a timer?
        bne     $a0, 0, timer_interrupt

        and     $a0, $k0, REQUEST_PUZZLE_INT_MASK       # Is there a puzzle?
        bne     $a0, 0, request_puzzle_interrupt

        and     $a0, $k0, MAX_GROWTH_INT_MASK           # Is there a max growth?
        bne     $a0, 0, max_growth_interrupt

        and     $a0, $k0, ON_FIRE_MASK                  # Is there a fire?
        bne     $a0, 0, on_fire_interrupt

        j       done
request_puzzle_interrupt:
        sw      $a1, REQUEST_PUZZLE_ACK # ack interrupt
        li      $a0, 1
        sw      $a0, puzzle_available_flag     # puzzle_available_flag = 1
        j       interrupt_dispatch
# Timer interrupts occur when we have arrived at a destination
timer_interrupt:
        sw      $a1, TIMER_ACK
        la      $a1, moving
        sw      $0, 0($a1)
        sw      $0, VELOCITY
        j       interrupt_dispatch
max_growth_interrupt:
        sw      $a1, MAX_GROWTH_ACK     # ack growth
        lw      $a0, MAX_GROWTH_TILE    # load max_growth location
        lw      $a1, max_growth_q_end   
        sw      $a0, 0($a1)             # store location to queue
        add     $a1, $a1, 4
        sw      $a1, max_growth_q_end   # increment queue end pointer
        j       interrupt_dispatch
on_fire_interrupt:
        sw      $a1, ON_FIRE_ACK
        lw      $a0, GET_FIRE_LOC
        lw      $a1, fire_q_end
        sw      $a0, 0($a1)             # store location to queue
        add     $a1, $a1, 4
        sw      $a1, max_growth_q_end   # increment queue end pointer
        j       interrupt_dispatch
done:
        la      $k0, chunkIH
        lw      $a0, 0($k0)
        lw      $a1, 4($k0)
        lw      $a2, 8($k0)
.set noat
        move    $at, $k1
.set at
        eret
