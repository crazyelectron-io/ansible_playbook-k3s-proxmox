# file:
# synopsis:

rule "VerisureDoorEvent" do
  description "Handle Verisure door sensor trigger"
  channel [
    'verisure:doorWindowSensor:myverisure:frontDoorSensor:doorWindowTriggerChannel',
    'verisure:doorWindowSensor:myverisure:garageDoorSensor:doorWindowTriggerChannel'
  ],
  triggered: ['DOORWINDOW_OPENED', 'DOORWINDOW_CLOSED']
  run { |trigger| logger.info "Verisure alarm channel(#{trigger.channel}) triggered event: #{trigger.event}" }
end
