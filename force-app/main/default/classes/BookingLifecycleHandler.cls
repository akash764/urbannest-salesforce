public with sharing class BookingLifecycleHandler {

    public static void validateSingleActiveBooking(List<Opportunity> newOpps) {
        Set<Id> houseIds = new Set<Id>();
        for (Opportunity opp : newOpps) {
            Id houseId = safeIdValue(opp, 'House_Unit__c');
            if (houseId != null && opp.StageName != 'Closed Lost') {
                if (houseIds.contains(houseId)) {
                    opp.addError('You cannot create multiple bookings for the same House Unit in the same transaction.');
                }
                houseIds.add(houseId);
            }
        }

        if (houseIds.isEmpty()) return;

        String query = 'SELECT Id, Name, House_Unit__c FROM Opportunity WHERE House_Unit__c IN ' + buildIdInClause(houseIds) + ' AND StageName != \'Closed Lost\'';
        List<SObject> existingRows = Database.query(query);

        Map<Id, SObject> activeBookingMap = new Map<Id, SObject>();
        for (SObject existing : existingRows) {
            Id existingHouseId = safeIdValue(existing, 'House_Unit__c');
            if (existingHouseId != null) {
                activeBookingMap.put(existingHouseId, existing);
            }
        }

        for (Opportunity opp : newOpps) {
            Id houseId = safeIdValue(opp, 'House_Unit__c');
            if (houseId != null && opp.StageName != 'Closed Lost' && activeBookingMap.containsKey(houseId)) {
                SObject activeOpp = activeBookingMap.get(houseId);
                if (activeOpp != null && activeOpp.get('Id') != opp.Id) {
                    opp.addError('This House Unit is already booked under active opportunity: ' + activeOpp.get('Name') + '. A house can have only one active booking.');
                }
            }
        }
    }

    public static void syncHouseStatusOnBookingChange(List<Opportunity> oppList, Map<Id, Opportunity> oldOppMap) {
        Map<Id, String> houseStatusMap = new Map<Id, String>();

        for (Opportunity opp : oppList) {
            Id houseId = safeIdValue(opp, 'House_Unit__c');
            if (houseId == null) continue;

            Boolean isInsert = (oldOppMap == null);
            Opportunity oldOpp = isInsert ? null : oldOppMap.get(opp.Id);

            if (isInsert && opp.StageName != 'Closed Lost') {
                houseStatusMap.put(houseId, 'Under Offer');
            } else if (!isInsert && opp.StageName != oldOpp.StageName) {
                if (opp.StageName == 'Key Handover') {
                    houseStatusMap.put(houseId, 'Occupied');
                } else if (opp.StageName == 'Construction Milestone') {
                    houseStatusMap.put(houseId, 'Sold');
                } else if (opp.StageName == 'Document Collection' || opp.StageName == 'Bank Sanction') {
                    houseStatusMap.put(houseId, 'Reserved');
                }
            }
        }

        if (!houseStatusMap.isEmpty()) {
            List<SObject> housesToUpdate = new List<SObject>();
            Schema.SObjectType houseType = Schema.getGlobalDescribe().get('House_Unit__c');
            if (houseType != null) {
                for (Id houseId : houseStatusMap.keySet()) {
                    SObject houseRecord = houseType.newSObject();
                    houseRecord.put('Id', houseId);
                    if (houseRecord.getSObjectType().getDescribe().fields.getMap().containsKey('Status__c')) {
                        houseRecord.put('Status__c', houseStatusMap.get(houseId));
                    }
                    housesToUpdate.add(houseRecord);
                }
                update housesToUpdate;
            }
        }
    }

    private static Id safeIdValue(SObject record, String fieldApiName) {
        if (record == null || String.isBlank(fieldApiName)) return null;
        if (!record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldApiName)) {
            return null;
        }
        Object value = record.get(fieldApiName);
        return value == null ? null : (Id) value;
    }

    private static String buildIdInClause(Set<Id> values) {
        if (values == null || values.isEmpty()) {
            return '(NULL)';
        }
        List<String> formatted = new List<String>();
        for (Id value : values) {
            formatted.add('\'' + String.escapeSingleQuotes(String.valueOf(value)) + '\'');
        }
        return '(' + String.join(formatted, ', ') + ')';
    }
}
