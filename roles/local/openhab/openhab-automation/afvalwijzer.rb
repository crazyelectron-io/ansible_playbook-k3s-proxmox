# # file: conf/automation/ruby/afvalwijzer.rb
# # snopsis: Get garbage collection dates from afvalwijzer.nl

# # Creëer de volgende Items om met de afvalkalender te kunnen werken:
# #
# #      Group gAfvalData "Afval ophaaldata" <calendar> (gTuin)
# #      DateTime AfvalData_gft             "Groente, Fruit en Tuin [%1$ta %1$td/%1$tm]"  <garbage_gft>        (gAfvalData)
# #      DateTime AfvalData_papier          "Papier [%1$ta %1$td/%1$tm]"                  <garbage_papier>     (gAfvalData)
# #      DateTime AfvalData_restafval       "Restafval [%1$ta %1$td/%1$tm]"               <garbage_restafval>  (gAfvalData)
# #      DateTime AfvalData_pmd             "Plastic [%1$ta %1$td/%1$tm]"                 <garbage_pmd>        (gAfvalData)
# #      DateTime AfvalData_kca             "Chemisch [%1$ta %1$td/%1$tm]"                <garbage_kca>        (gAfvalData)
# #      DateTime AfvalData_volgendeDatum   "Volgende afvalophaaldag [%1$ta %1$td/%1$tm]" <clock>              (gAfvalData)
# #      String   AfvalData_volgendeType    "Volgende afvalophaalsoort"                                        (gAfvalData)


# module CONFIG
#   # NUMBER = "{{afvalwijzer_house_number}}",
#   # POSTAL_CODE = "{{afvalwijzer_postal_code}}",
#   # API_KEY = "{{afvalwijzer_api_key}}"
#   URL = "https://api.mijnafvalwijzer.nl/webservices/appsinput/"
# end


# # Get the JSON response from Afvalwijzer
# def getJSONResponse(httpUrl)
#   logger.debug "Sending HTTP GET to #{httpUrl}"
#   # Create the HTTP object
#   uri = URI.parse(httpUrl)
#   header = {'Content-Type': 'application/json', 'Accept': '*/*'}
#   http = Net::HTTP.new(uri.host, uri.port)
#   request = Net::HTTP::Get.new(uri.request_uri, header)
#   response = http.request(request)
#   logger.warn "Result #{response.code} (#{response.body}) - retrieving Afvalwijzer data @ #{httpUrl} failed" unless response.code == "200"
#   return nil ? response.code != "200" : JSON.parse(result)
# end


# # Get the pickup dates from the JSON result
# def processPickupdates(dates, afvalType, afvalTypeDescription, item, now=nil)








# rule "GetWasteData" do
#   description "Get the dates for waste collection"
#   triggers: [
#     triggers.GenericCronTrigger('0 50 22 * * ?'),
#     triggers.GenericCronTrigger('0 30 19 * * ?')
#   ]
#   run do
#     today = time.strftime('%Y-%m-%d')
#     uri = CONFIG::URL +"?method=postcodecheck&street=&postcode=#{CONFIG::POSTAL_CODE}&huisnummer=#{CONFIG::NUMBER}&toevoeging=&apikey=#{CONFIG::API_KEY}&app_name=afvalwijzer&platform=phone&mobiletype=android&afvaldata=#{CONFIG::API_KEY}&version=58&langs=nl`"
#     logger.info "Afvalwijzer URI: #{uri}"

#     response = getJSONResponse(uri);
#     ophaaldagen = response.ophaaldagen;
#     if ophaaldagen.response !== 'OK' then
#       logger.warn "Ongeldige respons bij het downloaden van ophaaldata van #{uri}: #{pickupdates.error}"
#       return nil
#     end
#     pickupdates = [];
#     return ophaaldagen.data.map(d => new pickupDate(time.LocalDate.parse(d.date, dateFormatter), d.type));
#   end
# end


#      execute: data => {
#          const { postcode, huisnummer, toevoeging } = CONFIG;
#          itemPrefix = CONFIG.itemPrefix ?? "AfvalData";

#          logger.debug(`Afval ophaaldata ophalen voor ${postcode}-${huisnummer}${toevoeging}`);
#          if ('afvalkalenderUri' in CONFIG && CONFIG.afvalkalenderUri)
#              pickupdates = getPickupdatesAfvalkalender(postcode, huisnummer, CONFIG.afvalkalenderUri);
#          else
#              pickupdates = getPickupdatesMijnafvalwijzer(postcode, huisnummer, toevoeging, CONFIG.apikey);

#              if (!pickupdates || pickupdates.length == 0) {
#              logger.warn(`Kon ophaaldata niet downloaden voor ${postcode}-${huisnummer}${toevoeging}`);
#              return;
#          }


#          processPickupdates(pickupdates, 'papier',    'oud papier',                              `${itemPrefix}_papier`);
#          processPickupdates(pickupdates, 'gft',       'groente-, fruit- en tuinafval',           `${itemPrefix}_gft`);
#          processPickupdates(pickupdates, 'restafval', 'restafval',                               `${itemPrefix}_restafval`);
#          processPickupdates(pickupdates, 'pmd',       'plastic- en metaalafval en drinkkartons', `${itemPrefix}_pmd`);
#          processPickupdates(pickupdates, 'kca',       'klein chemisch afval',                    `${itemPrefix}_kca`);

#          setNextDateAndType(pickupdates, `${itemPrefix}_volgendeDatum`, `${itemPrefix}_volgendeType`);
#      }
#  });

#  class pickupDate {
#      constructor(date, type) {
#          this.date = date;
#          this.type = type;
#      }
#  }
