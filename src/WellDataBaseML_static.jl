#module WellDataBaseML
import Mads
import NMFk
import FileIO
import JLD
import DataFrames
import Dates
import Cairo
import Fontconfig
#import CSV
#include("./WellDataBase.jl/src/WellDataBase.jl")
include("./ReadWellData_All.jl/ReadWellData_All.jl")

cvsread=["API", "Id", "WellId", "CasingType", "CementSacks", "UpperSetDepth", "LowerSetDepth",
"WellboreSize", "CasingSize", "UpperPerf", "LowerPerf", "UpperPerfTVD", "LowerPerfTVD", "TopDepth","BHLatitude", "BHLongitude",
"TrueVerticalDepth", "LateralLength", "ThermalMaturity", "PrimaryFormation", "WaterInjection", "GasInjection", "C02Injection", "TubingPressure",
"StimDate", "TotalProppantMass","TestDate", "TestOil", "DailyOil", "OilGravity", "TestGas"]

dfs, dfs_header, api_static = ReadWellData_All.read_static(["csv-201908102241", "csv-201908102238", "csv-201908102239"]; location="./data/eagleford-play-20191008", cvsread=cvsread, downselect=[:WellType=>"GAS", :Orientation=>"Horizontal"])
FileIO.save("data/eagleford-play-20191008_static.jld2", "dfs", dfs, "dfs_header", dfs_header, "api_static", api_static)

df, df_header, api, recordlength, dates = ReadWellData_All.read_transient(["csv-201908102241", "csv-201908102238", "csv-201908102239"]; location="./data/eagleford-play-20191008", downselect=[:WellType=>"GAS", :Orientation=>"Horizontal"])
FileIO.save("data/eagleford-play-20191008_transient.jld2", "df", df, "df_header", df_header, "api", api, "recordlength", recordlength, "dates", dates)

df, df_header, api, recordlength, dates = FileIO.load("data/eagleford-play-20191008_transient.jld2", "df", "df_header", "api", "recordlength", "dates")
dfs, dfs_header, api_static = FileIO.load("data/eagleford-play-20191008_static.jld2", "dfs", "dfs_header", "api_static")
dfs = coalesce.(dfs, NaN)

stepsize = 1
syears = [2015, 2016, 2017]
# syears = [2015]
eyears = syears .+ stepsize

# NMFk.progressive(syears, eyears, startdate, df, df_header, api; nNMF=100, loading=true, problem="gaswellshor-20191008", figuredirdata="figures-data-eagleford", resultdir="results-nmfk-eagleford", figuredirresults="figures-nmfk-eagleford", scale=false, normalize=true)
oilm, fwells = NMFk.df2matrix(df, api, dates, :WellOil; addup=false)
oils, startdates, enddates = NMFk.df2matrix_shifted(df, api, recordlength, dates, :WellOil; addup=false)

sort!(df)
sort!(dfs)
dfs_data = DataFrames.DataFrame(repeat([Float64], inner=size(dfs)[2]) , names(dfs), size(api)[1])
dfs_data[!, :API] = api
goodwells = falses(size(dfs)[1])
for API in dfs[:, :API]
	@info("$API")
	iwell = df[!, :API] .== API
	ind = findfirst(x -> x == API, dfs[:,:API])
	api_ind = findfirst(x -> x == API, api)
	if sum(iwell) > 0
		dfs_data[api_ind, :] = dfs[ind, :]
		goodwells[ind] = 1
	end
end

dfs_mat = transpose(convert(Matrix,dfs_data))
oils_static = vcat(dfs_mat, oils)
# merge dfs data with oils

@JLD.save "data/eagleford-play-oil-20191008-shifted.jld" oils startdates enddates
@JLD.save "data/eagleford-play-oil-20191008-shifted-static.jld" oils_static startdates enddates
oils, startdates, enddates = JLD.load("data/eagleford-play-oil-20191008-shifted.jld", "oils", "startdates", "enddates")
oils_static, startdates, enddates = JLD.load("data/eagleford-play-oil-20191008-shifted-static.jld", "oils_static", "startdates", "enddates")
oils_static_nm, oils_min, oils_max = NMFk.normalizematrix_row(oils_static)
#
# add dfs to start of oils
#
static_length = size(dfs_data)[2]
NMFk.execute(oils_static[1:12 + static_length,:], 2:10; resultdir="results-nmfk-eagleford-20191008-static-nm", casefilename="oil_12", method=:simple, load=true)

ds = [0, 3, 6, 12, 18, 24, 36] # number of months in production

# execute NMFk using differing months of production on oils n(wells)xi(months)
for i in ds
	NMFk.execute(oils_static[1:i+static_length,:], 2:10; resultdir="results-nmfk-eagleford-20191008-static-nm-202108", casefilename="oil_$i", method=:simple, load=true)
end

dk = [4, 4, 4, 6, 5, 5, 3] # number of signals

for i = 1:length(ds)
	@info "Case" ds[i] dk[i]
	NMFk.load(2:10; resultdir="results-nmfk-eagleford-20191008-static-nm-202108", casefilename="oil_$(ds[i])")
end

#load NMFk results using only first few months, then run on entire time series fixing H used on training data
for i = 1:length(ds)
	W, H, fitquality, robustness, aic = NMFk.load(dk[i]; resultdir="results-nmfk-eagleford-20191008-static-nm-202108", casefilename="oil_$(ds[i])")
	Wall, Hall, fitquality, robustness, aic = NMFk.execute(oils_static[:,:], dk[i]; Hinit=convert.(Float64, H), Hfixed=true, resultdir="results-nmfk-eagleford-20191008-static-nm-202108", casefilename="oil_$(ds[i])_all", load=true)
end

# Calculate Oil production using the matrix results from NMFk runs
# Compare to true values
# Plot 1:1 scatter figure
import CSV
import DataFrames
for j = 1:length(ds)
	Wall, Hall, fitquality, robustness, aic = NMFk.load(dk[j]; resultdir="results-nmfk-eagleford-20191008-static-nm", casefilename="oil_$(ds[j])_all")
	Oall = Wall * Hall
	global nw = 0
	oil_t = Array{Float64}(undef, 0)
	oil_p = Array{Float64}(undef, 0)
	for (i, s) in enumerate(api)
		truth = NMFk.sumnan(oils_static[static_length+1:end,i])
		r = findlast(.!isnan.(oils_static[:,i]))
		pred = sum(Oall[static_length+1:r,i])
		if r > ds[j]
			push!(oil_p, pred)
			push!(oil_t, truth)
		end
	end
	oil_p_filt = oil_p[oil_t .> 1]
	oil_t_filt = oil_t[oil_t .> 1]
	r2 = NMFk.r2(oil_t, oil_p) #calculate r^squared
	@info("Window $(ds[j]) months $(length(oil_t)) R2: $r2")
	display(NMFk.plotscatter(oil_t, oil_p; filename="figures-predictions-eagleford-20191008-static-nm/oil-scatter-$(ds[j])-$(dk[j])-nm.png", title="Oil prediction: Window $(ds[j]) months r2 = $(round(r2; sigdigits=3))", xtitle="Truth", ytitle="Prediction"))
	using DataFrames
	df = DataFrame(modeled = oil_p, 
               observations = oil_t)
	using CSV
	CSV.write("data/$(ds[j])-$(dk[j])-static-nm.csv", df)
end

end
