module WellDataBaseML

import FileIO
import JLD
import JLD2
import DataFrames
import Dates
import WellDataBase
import NMFk
import Mads

function execute(syears::AbstractVector, eyears::AbstractVector, datadirs::AbstractVector; workdir::AbstractString=".", location::AbstractString="data/eagleford-play-20191008", labels=[:WellOil], skipstring=true, cvsread=["API", "ReportDate", "WellOil", "WellGas", "WellWater"], checkzero::Bool=true, downselect::AbstractVector=[], plotseries::Bool=true)
	df, df_header, api, recordlength, dates = WellDataBase.read(datadirs; location=joinpath(workdir, location), labels=labels, skipstring=skipstring, cvsread=cvsread, checkzero=checkzero, downselect=downselect)

	FileIO.save(joinpath(workdir, location) * ".jld2", "df", df, "df_header", df_header, "api", api, "recordlength", recordlength, "dates", dates)

	df, df_header, api, recordlength, dates = FileIO.load(joinpath(workdir, location) * ".jld2", "df", "df_header", "api", "recordlength", "dates")

	NMFk.progressive(syears, eyears, df, df_header, api; nNMF=100, load=true, problem="gaswellshor-20191008", figuredirdata=joinpath(workdir, "figures-data-eagleford"), resultdir=joinpath(workdir, "results-nmfk-eagleford"), figuredirresults=joinpath(workdir, "figures-nmfk-eagleford"), scale=false, normalize=true, plotr2pred=false, plotseries=plotseries)

	return df, df_header, api, recordlength, dates
end

function execute(syears::AbstractVector, eyears::AbstractVector, df::DataFrames.DataFrame, df_header::DataFrames.DataFrame, api; workdir::AbstractString=".", plotseries::Bool=true)
	NMFk.progressive(syears, eyears, df, df_header, api; nNMF=100, load=true, problem="gaswellshor-20191008", figuredirdata=joinpath(workdir, "figures-data-eagleford"), resultdir=joinpath(workdir, "results-nmfk-eagleford"), figuredirresults=joinpath(workdir, "figures-nmfk-eagleford"), scale=false, normalize=true, plotr2pred=false, plotseries=plotseries)
end

function execute(df::DataFrames.DataFrame, df_header::DataFrames.DataFrame, api, recordlength, dates; workdir::AbstractString="/Users/vvv/Julia/UnconventionalML.jl")
	oilm, fwells = NMFk.df2matrix(df, api, dates, :WellOil; addup=false)
	Mads.plotseries(oilm, "figures-data/oil.png"; xaxis=collect(dates))

	oils, startdates, enddates = NMFk.df2matrix_shifted(df, api, recordlength, dates, :WellOil; addup=false)

	@JLD.save "data/eagleford-play-oil-20191008-shifted.jld" oils startdates enddates

	oils, startdates, enddates = JLD.load("data/eagleford-play-20191008-oil-shifted.jld", "oils", "startdates", "enddates")

	NMFk.execute(oils[1:12,:], 2:10; resultdir="results-nmfk-eagleford-20191008", casefilename="oil_12", method=:simple, load=true)

	ds = [3, 6, 12, 18, 24, 36]
	for i in ds
		NMFk.execute(oils[1:i,:], 2:10; resultdir="results-nmfk-eagleford-20191008", casefilename="oil_$i", method=:simple, load=true)
	end

	dk = [3, 6, 6, 5, 4, 4]

	for i = 1:length(ds)
		@info "Case" ds[i] dk[i]
		NMFk.load(2:10; resultdir="results-nmfk-eagleford-20191008", casefilename="oil_$(ds[i])")
	end

	for i = 1:length(ds)
		W, H, fitquality, robustness, aic = NMFk.load(dk[i]; resultdir="results-nmfk-eagleford-20191008", casefilename="oil_$(ds[i])")
		Wall, Hall, fitquality, robustness, aic = NMFk.execute(oils[:,:], dk[i]; Hinit=convert.(Float32, H), Hfixed=true, resultdir="results-nmfk-eagleford-20191008", casefilename="oil_$(ds[i])_all", load=true)
	end

	for j = 1:length(ds)
		Wall, Hall, fitquality, robustness, aic = NMFk.load(dk[j]; resultdir="results-nmfk-eagleford-20191008", casefilename="oil_$(ds[j])_all")
		Oall = Wall * Hall
		global nw = 0
		oil_t = Array{Float64}(undef, 0)
		oil_p = Array{Float64}(undef, 0)
		for (i, s) in enumerate(api)
			truth = NMFk.sumnan(oils[:,i])
			r = findlast(.!isnan.(oils[:,i]))
			pred = sum(Oall[1:r,i])
			if r > ds[j]
				push!(oil_p, pred)
				push!(oil_t, truth)
			end
		end
		r2 = NMFk.r2(oil_t, oil_p)
		@info("Window size: $(ds[j]) months;  Number of wells: $(length(oil_t)); R2: $(round(r2; sigdigits=3))")
		display(NMFk.plotscatter(oil_t, oil_p; filename="figures-predictions-eagleford-20191008/oil-scatter-$(ds[j])-$(dk[j]).png", title="Window size: $(ds[j]) months; Number of wells: $(length(oil_t)); R2 = $(round(r2; sigdigits=3))", xtitle="Truth", ytitle="Prediction"))
	end
end

end
