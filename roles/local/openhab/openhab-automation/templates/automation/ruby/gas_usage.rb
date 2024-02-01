# file: conf/automation/ruby/gas_usage.rb
# synopsis: Calculate gas usage for last hour/day/month

profile :set_uom_dm3 do |event, callback:, state: nil|
  next true unless event == :state_from_handler # only handle state updates from handlers
  next true unless state.is_a?(DecimalType) # if it sent a QuantityType, process as normal. Could also possibly process this to discard the unit, and re-interpret -- not convert -- as a different unit.

  callback.send_update(state | "dm³") # forward the update, but as a QuantityType with unit dm³
  false # let it know we already processed the event, and it doesn't need to be handled again
end


rule "CalcGasUse" do
  description "Calculate the gas usage per hour/day/month/year (from DSMR readings)"
  changed Gas_Use_Total
  run do |event|
    logger.info "Update Gas usage stats triggered by #{event.item.name} [#{event.state}]"
    # Calculate hour/day/month gas delta
    deltaHour = event.item.delta_since(1.hour.ago)
    logger.info "Retrieved delta #{deltaHour}"
    Gas_Use_Hour << deltaHour unless deltaHour.nil?
    event.item.delta_since(LocalTime::MIDNIGHT)&.then { |delta| items["Gas_Use_Day"] << delta }
    event.item.delta_since(Date.new(Date.today.year, Date.today.month, 1).to_time)&.then { |delta| items["Gas_Use_Month"] << delta }
  end
end


rule "GasResetMidnight" do
  description "Reset Gas usage day total at midnight"
  every :day
  run do |event|
    Gas_Use_Day << 0 | "m³"
    logger.info "Reset Gas day usage at midnight"
  end
end
