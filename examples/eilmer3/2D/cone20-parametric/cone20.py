# cone20.py
# Simple job-specification file for e3prep.py
# PJ, 25-Sep-2014 -- parametric version

job_title = "Mach 1.5 flow over a 20 degree cone."
print job_title

# We can set individual attributes of the global data object.
gdata.dimensions = 2
gdata.title = job_title
gdata.axisymmetric_flag = 1

# Accept defaults for air giving R=287.1, gamma=1.4
select_gas_model(model='ideal gas', species=['air'])

# Define flow conditions
initial = FlowCondition(p=5955.0,  u=0.0,    v=0.0, T=304.0)
inflow  = FlowCondition(p=95.84e3, u=1000.0, v=0.0, T=1103.0)

# Set up two quadrilaterals in the (x,y)-plane by first defining
# the corner nodes, then the lines between those corners.
H = 1.0  # overall height of domain
L = 1.0  # overall length of domain
L1 = 0.2 # length to tip
alpha = math.radians(20.0)
a = Node(0.0, 0.0, label="A")
b = Node(L1, 0.0, label="B")
c = Node(L, math.sin(alpha)*(L-L1), label="C")
d = Node(L,  H, label="D")
e = Node(L1, H, label="E")
f = Node(0.0, H, label="F")
ab = Line(a, b); bc = Line(b, c) # lower boundary including cone surface
fe = Line(f, e); ed = Line(e, d) # upper boundary
af = Line(a, f); be = Line(b, e); cd = Line(c, d) # vertical lines

# Define the blocks, with particular discretisation.
nx0 = 10; nx1 = 30; ny = 40
blk_0 = Block2D(make_patch(fe, be, ab, af), nni=nx0, nnj=ny,
                fill_condition=initial, label="BLOCK-0")
blk_1 = Block2D(make_patch(ed, cd, bc, be, "AO"), nni=nx1, nnj=ny,
                fill_condition=initial, label="BLOCK-1",
                hcell_list=[(9,0)], xforce_list=[0,0,1,0])

# Set boundary conditions.
identify_block_connections()
blk_0.bc_list[WEST] = SupInBC(inflow, label="inflow-boundary")
blk_1.bc_list[EAST] = ExtrapolateOutBC(label="outflow-boundary")

# Do a little more setting of global data.
gdata.max_time = 5.0e-3  # seconds
gdata.max_step = 3000
gdata.dt = 1.0e-6
gdata.dt_plot = 1.5e-3
gdata.dt_history = 10.0e-5

sketch.xaxis(0.0, L, L/5, -0.05)
sketch.yaxis(0.0, H, H/5, -0.04)
sketch.window(0.0, 0.0, L, H, 0.05, 0.05, 0.17, 0.17)