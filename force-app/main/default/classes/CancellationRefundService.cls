public with sharing class CancellationRefundService {

    public static Date calculateRefundDueDate(Date approvalDate) {
        if (approvalDate == null) return null;

        Date dueDate = approvalDate;
        Integer businessDaysToAdd = 3;
        while (businessDaysToAdd > 0) {
            dueDate = dueDate.addDays(1);
            DateTime dt = DateTime.newInstance(dueDate.year(), dueDate.month(), dueDate.day());
            String dayOfWeek = dt.format('EEEE');
            if (dayOfWeek != 'Saturday' && dayOfWeek != 'Sunday') {
                businessDaysToAdd--;
            }
        }
        return dueDate;
    }

    public static void onCancellationApproved(List<Cancellation_Refund__c> approvedRecords) {
        for (Cancellation_Refund__c cr : approvedRecords) {
            safePut(cr, 'Approval_Status__c', 'Approved');
            safePut(cr, 'Approved_Date__c', Date.today());
            safePut(cr, 'Refund_Due_Date__c', calculateRefundDueDate(Date.today()));
        }
    }

    public static void onRefundCompleted(List<Cancellation_Refund__c> refundRecords, Map<Id, Cancellation_Refund__c> oldMap) {
        Set<Id> completedOppIds = new Set<Id>();

        for (Cancellation_Refund__c cr : refundRecords) {
            Object oldValue = oldMap != null && oldMap.containsKey(cr.Id) ? safeGet(oldMap.get(cr.Id), 'Refund_Completed_Date__c') : null;
            Object newValue = safeGet(cr, 'Refund_Completed_Date__c');
            Boolean wasCompletedBefore = oldValue != null;
            Id opportunityId = safeIdValue(cr, 'Opportunity__c');
            if (newValue != null && !wasCompletedBefore && opportunityId != null) {
                completedOppIds.add(opportunityId);
            }
        }

        if (completedOppIds.isEmpty()) return;

        String oppQuery = 'SELECT Id, StageName, House_Unit__c FROM Opportunity WHERE Id IN ' + buildInClause(completedOppIds);
        List<SObject> oppRows = Database.query(oppQuery);

        List<SObject> housesToRelease = new List<SObject>();
        Schema.SObjectType houseType = Schema.getGlobalDescribe().get('House_Unit__c');

        for (SObject opp : oppRows) {
            safePut(opp, 'StageName', 'Closed Lost');
            Id houseId = safeIdValue(opp, 'House_Unit__c');
            if (houseId != null && houseType != null) {
                SObject houseRecord = houseType.newSObject();
                houseRecord.put('Id', houseId);
                if (houseRecord.getSObjectType().getDescribe().fields.getMap().containsKey('Status__c')) {
                    houseRecord.put('Status__c', 'Available');
                }
                housesToRelease.add(houseRecord);
            }
        }

        update oppRows;
        if (!housesToRelease.isEmpty()) {
            update housesToRelease;
        }
    }

    private static String buildInClause(Set<Id> ids) {
        if (ids == null || ids.isEmpty()) {
            return '(NULL)';
        }
        List<String> values = new List<String>();
        for (Id idValue : ids) {
            values.add('\'' + String.escapeSingleQuotes(String.valueOf(idValue)) + '\'');
        }
        return '(' + String.join(values, ', ') + ')';
    }

    private static Object safeGet(SObject record, String fieldApiName) {
        if (record == null || String.isBlank(fieldApiName)) return null;
        if (!record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldApiName)) {
            return null;
        }
        return record.get(fieldApiName);
    }

    private static Id safeIdValue(SObject record, String fieldApiName) {
        if (record == null || String.isBlank(fieldApiName)) return null;
        if (!record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldApiName)) {
            return null;
        }
        Object value = record.get(fieldApiName);
        return value == null ? null : (Id) value;
    }

    private static void safePut(SObject record, String fieldApiName, Object value) {
        if (record == null || String.isBlank(fieldApiName)) return;
        if (record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldApiName)) {
            record.put(fieldApiName, value);
        }
    }
}
