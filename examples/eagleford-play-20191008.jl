import WellDataBaseML
import WellDataBase

stepsize = 1
syears = [2015, 2016, 2017]
# syears = [2015]
eyears = syears .+ stepsize

WellDataBaseML.execute(syears, eyears, ["csv-201908102241", "csv-201908102238", "csv-201908102239"]; location="data/eagleford-play-20191008", downselect=[:WellType=>"GAS", :Orientation=>"Horizontal"], workdir="/Users/vvv/Julia/UnconventionalML.jl")

df, df_header, api, recordlength, dates = WellDataBase.read(["csv-201908102241", "csv-201908102238", "csv-201908102239"]; location="/Users/vvv/Julia/UnconventionalML.jl/data/eagleford-play-20191008", downselect=[:WellType=>"GAS", :Orientation=>"Horizontal"])

WellDataBaseML.execute(syears, eyears, df, df_header, api; workdir="/Users/vvv/Julia/UnconventionalML.jl")