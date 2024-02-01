# file: conf/automation/ruby/solar_summary.rb   20230127
# synopsis: Calulate and summarize the solar production totals (Y/M/D/H)

module Prices
  PRICE = {
    # Format = Date range: Tariff 1 price, Tariff 2 price, limit
    (Date.parse('01-01-2023')..Date.parse('28-02-2023')) => [0.40, 0.40, 2900],
    (Date.parse('01-03-2023')..Date.parse('31-08-2023')) => [0.40, 0.39946, 2900],
    (Date.parse('01-09-2023')..Date.parse('31-12-2023')) => [0.408, 0.3772, 2900],
    (Date.parse('01-01-2024')..Date.parse('31-08-2026')) => ['0.3871 €/kWh', '0.3871 €/kWh', 10000],
  }
  CONTRACT_START = '2023-09-01'
end


rule "SetPowerTotal" do
  description "Add the Tarif 1 and Tarif 2 Electricity (DSMR) meter readings"
  changed gPowerTotal.members
  run do |event|
    prefix = "Power_" + event.item.name.split('_')[1]
    powerItem = items[prefix+"_Total"]
    logger.info "DBG90: [#{powerItem.name}] [#{powerItem.state}] #{event}"
    # Calculate hour/day/month power delta
    powerItem.delta_since(1.hour.ago)&.then { |delta| items[prefix+"_Hour"] << delta }
    delta = powerItem.delta_since(1.hour.ago)
    logger.info "DBG91: Delta [#{delta}]"
    items[prefix+"_Hour"] << delta
    powerItem.delta_since(LocalTime::MIDNIGHT)&.then { |delta| items[prefix+"_Day"] << delta }
    powerItem.delta_since(Date.new(Date.today.year, Date.today.month, 1).to_time)&.then { |delta| items[prefix+"_Month"] << delta }
    # Calculate last hour's power delta usage and cost
    unless Power_Use_Hour.state.nil? and Power_Ret_Hour.nil?
      logger.info "DBG97: Power_Use_Hour=[#{Power_Use_Hour.state}]; Power_Ret_Hour=[#{Power_Ret_Hour.state}]"
      Power_Delta_Hour << (Power_Use_Hour.state.nil? ? 0 | "kWh" : Power_Use_Hour.state) - (Power_Ret_Hour.state.nil? ? 0 | "kWh" : Power_Ret_Hour.state)
      Power_Delta_Hour_Cost << (Power_Delta_Hour.state / 1000) * Power_Price.state
    end
    # Calculate today's power delta usage and cost
    unless Power_Use_Day.state.nil? and Power_Ret_Day.state.nil?
      logger.info "DBG98: Power_Use_Day=[#{Power_Use_Day.state}]; Power_Ret_Day=[#{Power_Ret_Day.state}]"
      Power_Delta_Day << (Power_Use_Day.state.nil? ? 0 | "kWh" : Power_Use_Day.state) - (Power_Ret_Day.state.nil? ? 0 | "kWh" : Power_Ret_Day.state)
      Power_Delta_Day_Cost << (Power_Delta_Day.state / 1000) * Power_Price.state
    end
    # Calculate this month's power delta usage and cost
    unless Power_Use_Month.state.nil? and Power_Ret_Month.state.nil?
      logger.info "DBG99: Power_Use_Month=[#{Power_Use_Month.state}]; Power_Ret_Month=[#{Power_Ret_Month.state}]"
      Power_Delta_Month << (Power_Use_Month.state.nil? ? 0 | "kWh" : Power_Use_Month.state) - (Power_Ret_Month.state.nil? ? 0 | "kWh" : Power_Ret_Month.state)
      Power_Delta_Month_Cost << (Power_Use_Month.state - Power_Ret_Month.state) / 1000 * Power_Price.state
    end
  end
end


rule "CalcSolarSummary" do
  description "Update the solar panel production prices and totals"
  changed Solar_Prod_Day, Solar_Prod_Month, Solar_Prod_Year
  run do |event|
    Watchdog_Solar.ensure.on for: 30.minutes
    logger.debug "Update Solar Summary triggered by #{event} [#{event.state}]"
    items[event.item.name+'_Cost'] << event.state * Power_Price.state
    event.item.delta_since(1.hour.ago)&.then { |delta| Solar_Prod_Hour << delta } if event.item.name == "Solar_Prod_Day"
  end
end


# rule "SolarResetMidnight" do
#   description "Reset solar day totals at midnight"
#   every :day
#   run do |event|
#     Solar_Prod_Day_Summary.update("0.0 kWh, EUR 0.00")
#     logger.info "Reset Solar day summery at midnight"
#   end
# end


rule "SetElectrictyPrice" do
  description "Set the kWh price of electricity based on current tariff"
  changed Power_Tariff
  run do |event|
    myprice = Prices::PRICE.select { |range| range === Date.today }
    Power_Price << myprice.values[0][Power_Tariff.state - 1]
  end
end


rule "DSMRPhasesDelta" do
  description "Calculate the current delta in power consumption per phase"
  changed gPowerPhase.members
  run do |event|
      phase = event.item.name.split('_')[2]
      items["Power_Delta_"+phase+"_Current"] << items["Power_Use_"+phase+"_Current"].state - items["Power_Ret_"+phase+"_Current"].state
      Power_Delta_All_Current << Power_Use_All_Current.state - Power_Ret_All_Current.state
    end
end
