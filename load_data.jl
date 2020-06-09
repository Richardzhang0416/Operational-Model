using CSV, JuMP, Gurobi, LinearAlgebra

#Read the data
y15 = CSV.read("Y15_v4.csv");
T = y15[:,1]; #total periods
TPD  = y15[:,3]; #set of total demand
SS = [1,2,3];   #set of slices
WS = [0.25,0.5,0.25]; #set of weight of slices
S1 = y15[337:384,1]; #array of slice 1
S2= y15[4369:4416,1]; #array of slice 2
S3=y15[9457:9504,1]; #arracy of slice 3

TExt = y15[:,6]; #exterior temperature
pGW_15 = y15[:,4]; #2015 wind power
pGS_15 = y15[:,5]; #2015 solar power

#time period for operational model
#TO = y15[4086:4421,1]
#TTT = hcat(TO,TO,TO)

#time period for planning model
S1 = y15[337:384,1]; #array of slice 1
S2= y15[4369:4416,1]; #array of slice 2
S3=y15[9457:9504,1]; #arracy of slice 3
TT = hcat(S1,S2,S3); #total periods in all slices

gen_type = CSV.read("gen_type.csv");
G   = gen_type[1:4,1];  #set of conventional generator
W   = gen_type[1:5,2]; #set of wind gnereator
S   = gen_type[1:1,3]; #set of solar generator
ES  = gen_type[1:1,4]; #set of electricity
HS  = gen_type[1:1,5]; #set of heat store

gen_info = CSV.read("con_info.csv"); #information of conventional generator
EG = gen_info[:,1]; #efficiency of  gnereator
FG_CPX = gen_info[:,4]; #CAPEX of generator
FG_OM = gen_info[:,3]; #OPEX of generator
YG = gen_info[:,5]; #life of gnereator
EM = gen_info[:,7]; #co2 emission per tonee
CG = gen_info[:,2]; #cost of generator
CFuel = gen_info[:,8]; #cost of fuel
PGmax = gen_info[:,6]; #generator limits

wind_info = CSV.read("wind_info.csv");
WF = wind_info[:,9:14]; #wind pattern
EW = wind_info[1:5,2]; #efficiency of wind farm
FW_CPX = wind_info[1:5,5]; # CAPEX of wind
FW_OM = wind_info[1:5,4]; #OPEX of wind
YW = wind_info[1:5,6]; #life of wind
Wcap_15 = wind_info[1:5,7]; #wind capcity in 2015


solar_info = CSV.read("solar_info.csv");
ES = solar_info[:,1]; #efficiency of solarpv
FS_CPX = solar_info[:,4]; #CAPEX of solar
FS_OM = solar_info[:,3]; #OPEX of solar
YS = solar_info[:,5]; #life of solar
Scap_15 = solar_info[1,6]; #solar capacity in 2015

HS_info = CSV.read("Hstore_info.csv");
EHS_h = HS_info[:,1]; #efficiency of heating a store
EHS_c = HS_info[:,11];
CHeat = HS_info[:,2]; #cost of power go into the heat store
FHS_CPX = HS_info[:,4]; #fixed capex of heat store
YHS = HS_info[:,5]; #life of heat store
FHS_OM = HS_info[:,3]; #fixed om of heat store
Qmass = HS_info[1,6]; #Qmass
Ploss = HS_info[1,7]; #Ploss
THS_plus = HS_info[:,8]; #maximum allowed temperature of heat store
THS_minus = HS_info[:,9]; #minimum allowed temperature of heat store
PHS_plus_cap = HS_info[:,12]; #maximum power input

ES_info = CSV.read("Estore_info.csv");
CElect = ES_info[:,2]; #cost of power go into electricity store
EES = ES_info[:,1]; #efficiency of electricity store
FES_CPX = ES_info[:,4]; #capex of electricity store
YES = ES_info[:,5]; #life of electricity store
FES_OM = ES_info[:,3]; #fixed om of electricity store
ES_Ecap = ES_info[:,7]; #maximum energy level in the electricity store
FES_ECPX = ES_info[:,6]; #energy CAPX of electricity store
PES_plus_cap = ES_info[:,9]; #maximum power into electricity store es
PES_minus_cap = ES_info[:,10]; #maximum power out of electricity store es


other_info = CSV.read("other_info.csv");
CO2_tax = other_info[1,2]; #CO2 tax
CShed_load = other_info[2,2]; #cost of load shedding
CShed_gen = other_info[3,2]; #cost of generation shedding
Ht = other_info[4,2]; #numbder of hour in each period
CO2_max = other_info[5,2]; #maximum co2 emission allowed
H = other_info[6,2]; #number of hours in a day
Y = other_info[7,2]; #number of hours in a year

#CO2 cases
co2_info = CSV.read("co2_case.csv");
co2_case = co2_info[:,1]; #6 co2 cases
Z = co2_info[:,2]; #coefficient

#bus-line information
net_info = CSV.read("network_info.csv");
B = net_info[1:5,1]; #set of bus
BF = net_info[1:5,2]; #set of bus demand factors
L = net_info[1:7,3]; #set of line
FL_CPX = net_info[1:7,7]; #fixed capex of line
FL_OM = net_info[1:7,8]; #fixed opex of line
GLoc = net_info[1:4,10]; #generator location
WLoc = net_info[1:5,11]; #wind farm location
SLoc = net_info[1:1,12]; #solar loaction
HSLoc = net_info[1:1,21]; #heat store location
ESLoc = net_info[1:1,22]; #electricity store location
a = net_info[1:5,13:19]; #bus-line incidence matrix
LR = net_info[1:7,5]; #line capacity
Re_bus = net_info[1,20]; #reference bus
PLmax = net_info[1:7,4]; #line capacity
YL = net_info[1:7,6]; #life of line
