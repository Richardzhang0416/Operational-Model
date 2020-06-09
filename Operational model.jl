include("load_data.jl")
#function for the cycle
function nxt(t,TB,TE)
    if t< TE
        return t+1
    end
    if t>= TE
        return TB
    end
end

#Model
m=Model(Gurobi.Optimizer)

#decision variables
@variable(m, pG[G,TT]>=.0);#power output of gnereator g in period t
@variable(m, pHS_h[HS,TT]>=.0); #electricity power used to generate hs at the start of period t
@variable(m, pHS_c[HS,TT]>=.0); #electricity power used to cooler heat store hs
@variable(m, pHS_plus[HS,TT]>=.0); #heat power input to heat store
@variable(m, qHS[HS,TT]>=.0); #energy in heat store hs at the start of period t
@variable(m, tInt[HS,TT]>=.0); #interior temperature of heat store hs at the start of period t
@variable(m, pES_plus[ES,TT]>=.0); #power into store es during period t
@variable(m, pES_minus[ES,TT]>=.0); #power out of store es during period t
@variable(m, qES[ES,TT]>=.0); #level of energy at the start of period t
@variable(m, pGShed[B,TT]>=.0); #generation shed at period t at bus b
@variable(m, pLShed[B,TT]>=.0); #load shed at period t at bus b
@variable(m, pl[L,TT]); #power flow into line
@variable(m, delta[B,TT]); #phase angle

#variable for planning model
@variable(m, pGmax[G]>=.0); #capacities of gnereators
@variable(m, pES_plus_cap[ES]>=.0); #maximum power into electricity store es
@variable(m, pES_minus_cap[ES]>=.0); #maximum power out of electricity store es
@variable(m, qES_plus_cap[ES]>=.0); #maixmum level of storage of electricity store es
@variable(m, plmax[L]>=.0); #line limit of line l
@variable(m, pW_cap[W]>=.0); #installed wind capacity
@variable(m, pS_cap[S]>=.0); #installed soalr capacity
@variable(m, pHS_plus_cap[HS]>=.0); #maximum input power in heat store hs


#constraints
#conventional generator limits
@constraint(m, con_limit[g in G, s in SS, t in TT[:,s]], pG[g,t]<=PGmax[g]);

#renewable generator limits and demand at each bus
PGS = [2.5*pGS_15[t] for t in T for s in S]; #solar power available
pGW1 = [WF[:,w].*Wcap_15[w] for w in W];
PGW = hcat(pGW1[1],pGW1[2],pGW1[3],pGW1[4],pGW1[5]); #wind power avaiable in each region
hp = [30*pGS_15[t] for t in T]; #heating power from solar in 2015
PD = [TPD[t]*BF[b] for t in T, b in B]; #demand of bus b in period t


#electricity store
@constraint(m, ES_balance[es in ES, s in SS, t in TT[:,s]], qES[es,nxt(t, TT[1,s], TT[end,s])]==qES[es,t]+
Ht*(EES[es]*pES_plus[es,t]-pES_minus[es,t]));
@constraint(m, ES_input_limit[es in ES, s in SS, t in TT[:,s]], pES_plus[es,t]<=PES_plus_cap[es]);
@constraint(m, ES_output_limit[es in ES, s in SS, t in TT[:,s]], pES_minus[es,t]<=PES_minus_cap[es]);
@constraint(m, ES_energy_limit[es in ES, s in SS, t in TT[:,s]], qES[es,t] <= ES_Ecap[es]);


#heating store constraint
lambda = Ploss/Qmass
@constraint(m, HS_balance[hs in HS, s in SS, t in TT[:,s]], qHS[hs,nxt(t,TT[1,s],TT[end,s])]==exp(-lambda*Ht)*qHS[hs,t]+
((EHS_h[hs]*pHS_h[hs,t]+Ploss*TExt[t]+hp[t]-EHS_c[hs]*pHS_c[hs,t])/lambda)-
exp(-lambda*Ht)*((EHS_h[hs]*pHS_h[hs,t]+Ploss*TExt[t]+hp[t]-EHS_c[hs]*pHS_c[hs,t])/lambda));
@constraint(m, Heat_pump_power[hs in HS, s in SS, t in TT[:,s]], pHS_c[hs,t]<=PHS_plus_cap[hs]);
@constraint(m, HS_temp1[hs in HS, s in SS, t in TT[:,s]], tInt[hs,t]==qHS[hs,t]/Qmass);
@constraint(m, HS_temp2[hs in HS, s in SS, t in TT[:,s]], tInt[hs,t]>=THS_minus[hs]);
@constraint(m, HS_temp3[hs in HS, s in SS, t in TT[:,s]], tInt[hs,t]<=THS_plus[hs]);


#KCL
@constraint(m, KCL[ss in SS, t in TT[:,ss], b in B], sum(pG[g,t] for g in G if GLoc[g]==b) +
sum(PGW[t,w] for w in W if WLoc[w]==b) + sum(PGS[t,s] for s in S if SLoc[s]==b) + sum(a[b,l]*pl[l,t] for l in L) +pLShed[b,t]
+sum(pES_minus[es,t] for es in ES if ESLoc[es]==b)
==PD[t,b]+pGShed[b,t]+sum(pES_plus[es,t] for es in ES if ESLoc[es]==b)+sum(pHS_h[hs,t]+pHS_c[hs,t] for hs in HS if HSLoc[hs]==b))


#network constraint
@constraint(m, rebus[s in SS, t in TT[:,s]], delta[Re_bus,t]==0);
@constraint(m, KVL[l in L, s in SS, t in TT[:,s]], pl[l,t]==(-1/LR[l])*(sum(a[b,l]*delta[b,t] for b in B)));
@constraint(m, line_limit1[l in L, s in SS, t in TT[:,s]], pl[l,t]<=PLmax[l]);
@constraint(m, line_limit2[l in L, s in SS, t in TT[:,s]], pl[l,t]>=-PLmax[l]);

#CO2 emission
CO2E = [sum(((EM[g]*pG[g,t]*Ht)/EG[g])/H for g in G for t in TT[:,s]) for s in SS];
#weighted average hourly CO2 emission
weighted_CO2E = sum(WS[s]*CO2E[s] for s in SS);
# @constraint(m, CO2emission, weighted_CO2E<=CO2_max);


#CAPEX
# generator_capex = sum(((FG_CPX[g]/YG[g])+FG_OM[g])*pGmax[g]/Y for g in G)
# wind_capex = sum(((FW_CPX[w]/YW[w])+FW_OM[w])*pW_cap[w]/Y for w in W)
# solar_capex = sum((((FS_CPX[s]/YS[s])+FS_OM[s])*pS_cap[s])/Y for s in S)
# HS_capex = sum(((FHS_CPX[hs]/YHS[hs])+FHS_OM[hs])*pHS_plus_cap[hs]/Y for hs in HS)
# ES_capex = sum(((FES_CPX[es]/YES[es])+FES_OM[es])*pES_plus_cap[es]/Y for es in ES)
# ESE_capex = sum(((FES_ECPX[es]/YES[es]))*qES_plus_cap[es]/Y for es in ES)
# line_capex = sum(((FL_CPX[l]/YL[l])+FL_OM[l])*plmax[l]/Y for l in L)
# CAPEX = generator_capex+wind_capex+solar_capex+HS_capex+ES_capex+ESE_capex+line_capex;


#OPEX
operational_cost = [sum(((CG[g]*pG[g,t]*Ht)/H) for g in G for t in TT[:,s]) for s in SS];
fuel_cost = [sum((CFuel[g]*pG[g,t]/EG[g]*Ht)/H for g in G for t in TT[:,s]) for s in SS];
CO2_cost = [sum((CO2_tax*EM[g]*pG[g,t]*Ht/EG[g])/H for g in G for t in TT[:,s]) for s in SS];
GShed_cost = [sum(CShed_gen*pGShed[b,t]*Ht/H for t in TT[:,s] for b in B) for s in SS];
LShed_cost = [sum(CShed_load*pLShed[b,t]*Ht/H for t in TT[:,s] for b in B) for s in SS];
ES_cost = [sum(((CElect[es]*pES_plus[es,t]*Ht)/H) for es in ES for t in TT[:,s]) for s in SS];
HS_cost = [sum(CHeat[hs]*(pHS_h[hs,t]+pHS_c[hs,t])*Ht/H for t in TT[:,s] for hs in HS) for s in SS];
O= hcat(operational_cost, fuel_cost, CO2_cost, GShed_cost, LShed_cost, ES_cost,HS_cost);
OPEX = sum(((operational_cost[s]+fuel_cost[s]+CO2_cost[s]+GShed_cost[s]+LShed_cost[s]+ES_cost[s]
+HS_cost[s])*WS[s]) for s in SS);



@objective(m, Min, OPEX)


optimize!(m)

# open("planning reslut.txt","w") do io
#
#     println(io,"CAPEX:", value.(CAPEX))
#     println(io, "OPEX:", value.(OPEX))
#     for g in G
#         println(io, "Capacity of ", g, " " , value.(pGmax[g]))
#     end
#     for w in W
#         println(io, "Capacity of wind farm", w, " ", value.(pW_cap[w]))
#     end
#     for s in S
#         println(io, "Capacity of solar PV", s, " ", value.(pS_cap[s]))
#     end
#     println(io, "CO2 emission"," ", value.(weighted_CO2E))
#     for es in ES
#         println(io,"Input electric power capacity", " ", value.(pES_plus_cap[es]))
#         println(io, "PHSE storage capacity" , " ", value.(qES_plus_cap[es]))
#     end
#     for hs in HS
#         println(io, "Input power of heat store", " ", value.(pHS_plus_cap[hs]))
#     end
#     #println(io, "CO2 marginal cost", " ", dual.(CO2emission))
#     for l in L
#         println(io, "line capacity of ", " ",l,": ", value.(plmax[l]))
#     end
# end
#
#
# open("plot reslut.csv","w") do io
#             for t in TT[:,1]
#                     println(io,t,",", value.(pG[4,t]),",",value.(pG[4,t]+pG[3,t]),",",
#                     value.(pG[4,t]+pG[3,t]+pG[2,t]),",",value.(pG[4,t]+pG[3,t]+pG[2,t]+pG[1,t]),",",
#                     value.(pG[4,t]+pG[3,t]+pG[2,t]+pG[1,t]+sum(pGW[t,w] for w in W)),",",
#                     value.(pG[4,t]+pG[3,t]+pG[2,t]+pG[1,t]+sum(pGW[t,w] for w in W)+pGS[t,1]),","
#                     ,sum(PD[t,b] for b in B),","
#                     ,sum(PD[t,b] for b in B)+value.(pHS_h[1,t]))
#             end
# end
#
# open("wind reslut.csv","w") do io
#             for t in TT[:,3]
#                     println(io,t,",", value.(pGW[t,1]),",",value.(pGW[t,2]),",", value.(pGW[t,3]),",",
#                     value.(pGW[t,4]),",",value.(pGW[t,5]))
#             end
# end
