public without sharing class EnquiryController {

    public class ProjectSummary {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String state { get; set; }
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public String heroImageUrl { get; set; }
        @AuraEnabled public Decimal startingPrice { get; set; }
    }

    public class ProjectBrochureDetail {
        @AuraEnabled public Project__c project { get; set; }
        @AuraEnabled public List<Apartment__c> apartments { get; set; }
        @AuraEnabled public List<House_Unit__c> houseUnits { get; set; }
    }

    public class LeadEnquiryRequest {
        @AuraEnabled public String firstName { get; set; }
        @AuraEnabled public String lastName { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public Decimal budget { get; set; }
        @AuraEnabled public String bhkPreference { get; set; }
        @AuraEnabled public Id projectId { get; set; }
        @AuraEnabled public String remarks { get; set; }
    }

    public class LeadSubmissionResult {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Id leadId { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static List<ProjectSummary> getActiveProjects() {
        List<ProjectSummary> summaries = new List<ProjectSummary>();
        if (!doesObjectExist('Project__c')) return summaries;

        List<String> fields = getAvailableFields('Project__c', new List<String>{
            'Id', 'Name', 'State__c', 'Description__c', 'Hero_Image_URL__c'
        });
        if (fields.isEmpty()) return summaries;

        String query = 'SELECT ' + String.join(fields, ', ') + ' FROM Project__c ORDER BY Name ASC';
        for (SObject row : Database.query(query)) {
            ProjectSummary ps = new ProjectSummary();
            ps.id = (Id) row.get('Id');
            ps.name = safeString(row, 'Name');
            ps.state = safeString(row, 'State__c');
            ps.description = safeString(row, 'Description__c');
            ps.heroImageUrl = safeString(row, 'Hero_Image_URL__c');
            summaries.add(ps);
        }
        return summaries;
    }

    @AuraEnabled(cacheable=true)
    public static ProjectBrochureDetail getProjectBrochure(Id projectId) {
        if (projectId == null || !doesObjectExist('Project__c')) return null;

        ProjectBrochureDetail detail = new ProjectBrochureDetail();

        List<String> projectFields = getAvailableFields('Project__c', new List<String>{
            'Id', 'Name', 'State__c', 'Description__c', 'Hero_Image_URL__c', 'Brochure_PDF_URL__c'
        });
        if (projectFields.isEmpty()) return detail;

        String projectQuery = 'SELECT ' + String.join(projectFields, ', ') + ' FROM Project__c WHERE Id = \'' + String.escapeSingleQuotes(String.valueOf(projectId)) + '\' LIMIT 1';
        List<SObject> projectRows = Database.query(projectQuery);
        if (!projectRows.isEmpty()) {
            detail.project = (Project__c) projectRows[0];
        }

        List<String> apartmentFields = getAvailableFields('Apartment__c', new List<String>{
            'Id', 'Name', 'Block_Name__c', 'Total_Floors__c', 'Total_Units__c', 'Photos__c', 'Project__c'
        });
        if (!apartmentFields.isEmpty()) {
            String apartmentQuery = 'SELECT ' + String.join(apartmentFields, ', ') + ' FROM Apartment__c WHERE Project__c = \'' + String.escapeSingleQuotes(String.valueOf(projectId)) + '\' ORDER BY Name ASC';
            List<Apartment__c> apartments = new List<Apartment__c>();
            for (SObject row : Database.query(apartmentQuery)) {
                apartments.add((Apartment__c) row);
            }
            detail.apartments = apartments;
        }

        List<String> houseFields = getAvailableFields('House_Unit__c', new List<String>{
            'Id', 'Name', 'Unit_Number__c', 'BHK_Type__c', 'Floor__c', 'Base_Price__c', 'Status__c', 'Apartment__c'
        });
        if (!houseFields.isEmpty()) {
            String houseQuery = 'SELECT ' + String.join(houseFields, ', ') + ' FROM House_Unit__c WHERE Apartment__r.Project__c = \'' + String.escapeSingleQuotes(String.valueOf(projectId)) + '\' ORDER BY Name ASC';
            List<House_Unit__c> houseUnits = new List<House_Unit__c>();
            for (SObject row : Database.query(houseQuery)) {
                houseUnits.add((House_Unit__c) row);
            }
            detail.houseUnits = houseUnits;
        }

        return detail;
    }

    @AuraEnabled
    public static LeadSubmissionResult submitEnquiry(LeadEnquiryRequest request) {
        LeadSubmissionResult result = new LeadSubmissionResult();

        if (request == null || String.isBlank(request.lastName) || (String.isBlank(request.email) && String.isBlank(request.phone))) {
            result.isSuccess = false;
            result.message = 'Please provide your name and contact details (email or phone).';
            return result;
        }

        try {
            String emailFilter = String.isBlank(request.email) ? '' : 'Email = \'' + String.escapeSingleQuotes(request.email) + '\'';
            String phoneFilter = String.isBlank(request.phone) ? '' : 'Phone = \'' + String.escapeSingleQuotes(request.phone) + '\'';
            String duplicateQuery = 'SELECT Id, Status, OwnerId FROM Lead WHERE IsConverted = false AND (' +
                (String.isBlank(emailFilter) ? '' : '(' + emailFilter + ')') +
                (String.isBlank(emailFilter) || String.isBlank(phoneFilter) ? '' : ' OR ') +
                (String.isBlank(phoneFilter) ? '' : '(' + phoneFilter + ')') +
                ') LIMIT 1';
            List<Lead> duplicates = Database.query(duplicateQuery);

            if (!duplicates.isEmpty()) {
                Lead existingLead = duplicates[0];
                Task followUpTask = new Task(
                    WhoId = existingLead.Id,
                    Subject = 'New Web Enquiry Submitted (Duplicate/Repeat Prospect)',
                    Description = 'Prospect submitted another enquiry. BHK: ' + request.bhkPreference + ', Budget: ' + request.budget + ', Project: ' + request.projectId,
                    Priority = 'High',
                    Status = 'Not Started'
                );
                insert followUpTask;

                result.isSuccess = true;
                result.message = 'Thank you! We have updated your existing enquiry, and our sales executive will contact you shortly.';
                result.leadId = existingLead.Id;
                return result;
            }

            Lead newLead = new Lead();
            newLead.FirstName = request.firstName;
            newLead.LastName = request.lastName;
            newLead.Email = request.email;
            newLead.Phone = request.phone;
            newLead.Company = 'Individual Prospect';
            newLead.LeadSource = 'Own Website';
            newLead.Status = 'New';
            safePut(newLead, 'Budget__c', request.budget);
            safePut(newLead, 'BHK_Preference__c', request.bhkPreference);
            safePut(newLead, 'Project_of_Interest__c', request.projectId);
            newLead.Description = request.remarks;

            Id assignedOwnerId = getNextRoundRobinOwner();
            if (assignedOwnerId != null) {
                newLead.OwnerId = assignedOwnerId;
            }

            insert newLead;

            result.isSuccess = true;
            result.message = 'Thank you for your interest! A sales executive has been assigned and will contact you shortly.';
            result.leadId = newLead.Id;
            return result;
        } catch (Exception ex) {
            result.isSuccess = false;
            result.message = 'Error submitting enquiry: ' + ex.getMessage();
            return result;
        }
    }

    private static Id getNextRoundRobinOwner() {
        List<User> salesReps = [
            SELECT Id, Name
            FROM User
            WHERE IsActive = true
              AND (UserRole.Name LIKE '%Sales%' OR Profile.Name LIKE '%Sales%')
            ORDER BY Name ASC
        ];

        if (salesReps.isEmpty()) {
            List<User> admins = [SELECT Id FROM User WHERE IsActive = true AND Profile.Name = 'System Administrator' LIMIT 1];
            return !admins.isEmpty() ? admins[0].Id : UserInfo.getUserId();
        }

        AggregateResult[] leadCounts = [
            SELECT OwnerId, COUNT(Id) cnt
            FROM Lead
            WHERE OwnerId IN :salesReps
              AND CreatedDate = TODAY
            GROUP BY OwnerId
            ORDER BY COUNT(Id) ASC
        ];

        Map<Id, Integer> countsByOwner = new Map<Id, Integer>();
        for (User u : salesReps) {
            countsByOwner.put(u.Id, 0);
        }
        for (AggregateResult ar : leadCounts) {
            countsByOwner.put((Id) ar.get('OwnerId'), (Integer) ar.get('cnt'));
        }

        Id selectedRepId = salesReps[0].Id;
        Integer minCount = 2147483647;
        for (User u : salesReps) {
            Integer count = countsByOwner.get(u.Id);
            if (count < minCount) {
                minCount = count;
                selectedRepId = u.Id;
            }
        }

        return selectedRepId;
    }

    private static Boolean doesObjectExist(String objectApiName) {
        return Schema.getGlobalDescribe().containsKey(objectApiName);
    }

    private static List<String> getAvailableFields(String objectApiName, List<String> candidateFields) {
        if (!doesObjectExist(objectApiName) || candidateFields == null || candidateFields.isEmpty()) {
            return new List<String>();
        }
        Map<String, Schema.SObjectField> fields = Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();
        List<String> actualFields = new List<String>();
        for (String fieldApiName : candidateFields) {
            if (fields.containsKey(fieldApiName)) {
                actualFields.add(fieldApiName);
            }
        }
        return actualFields;
    }

    private static String safeString(SObject record, String fieldApiName) {
        if (record == null || String.isBlank(fieldApiName) || !record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldApiName)) {
            return null;
        }
        Object value = record.get(fieldApiName);
        return value == null ? null : String.valueOf(value);
    }

    private static void safePut(SObject record, String fieldApiName, Object value) {
        if (record == null || String.isBlank(fieldApiName) || !record.getSObjectType().getDescribe().fields.getMap().containsKey(fieldApiName)) {
            return;
        }
        record.put(fieldApiName, value);
    }
}
