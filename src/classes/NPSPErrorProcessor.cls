/****
NPSP Email parser and register to handle collecting, collating and 
sorting error messages from NPSP users.  
Writes to a custom error object Error_Message__c
*/
global class NPSPErrorProcessor implements Messaging.InboundEmailHandler {
      
    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailresult();
      
        Error_Message__c em = new Error_Message__c(Message__c = email.plainTextBody);
        
        //convert email body to lowercase to avoid case mismatches
        string lcEmailBody = email.plainTextBody.toLowerCase().trim();
               
        //First, determine the error type - we'll search the 
        //body for some generic clues to determine the type        
        string emErrorContext = '';        
        if (lcEmailBody.contains('custom_validation'))        
            emErrorContext = emErrorContext + 'Validation Error;';
        if (lcEmailBody.contains('apex script unhandled trigger exception'))
            emErrorContext = emErrorContext + 'Apex Trigger;';
        if (lcEmailBody.contains('batch'))
            emErrorContext = emErrorContext + 'Batch Apex;';
        if (lcEmailBody.contains('visualforce'))
            emErrorContext = emErrorContext + 'Visualforce;';
        if (lcEmailBody.contains('apex script unhandled exception'))
            emErrorContext = emErrorContext + 'Apex Class;';
        //Finally, if we haven't found anything, dump it in 'other'
        if (emErrorContext.length() < 2)
            emErrorContext = 'Other;'; 
        
        em.Error_Context__c = emErrorContext;
        
        string regex = '005[A-Za-z0-9]{12}+/(00D[A-Za-z0-9]{12}+)[\\r\\n]+(.+?)[\\r\\n]+caused by:[\\s]*System\\.([^:]*)[\\s]*:(.+)[\\r\\n]+(?:(?:Class)|(?:Trigger))\\.([\\w]*)\\.([\\w]*)\\.?([\\w]*):';
        Pattern emailPattern = Pattern.compile(regex);
        
        Matcher emailMatcher = emailPattern.matcher(email.plainTextBody);
    
        if (emailMatcher.find()){ 
           
           //These will fail if no ID is found - however, both are parents and required for em
            sfLma__License__c errorLicense = [select id, sfLma__Package_Version__r.sfLma__Package__r.id, sfLma__Package_Version__r.id from sflma__License__c where sfLma__Subscriber_Org_ID__c = :emailMatcher.group(1).trim() and sflma__Status__c = 'Active' and sfLma__Package_Version__r.sfLma__Package__r.Namespace__c = :emailMatcher.group(5).trim()];
            em.License__c = errorLicense.id;       
            em.Package__c = errorLicense.sfLma__Package_Version__r.sfLma__Package__r.id; // [select id from sfLma__Package__c where Namespace__c = :emailMatcher.group(5).trim()].id;
            em.Package_Version__c = errorLicense.sfLma__Package_Version__r.id;
            em.Account__c = [select id from Account where Organization_ID__c = :emailMatcher.group(1).trim()].id;
            em.Exception_Type__c = emailMatcher.group(3).trim();        
            em.Short_Message__c = emailMatcher.group(4).trim();    
            em.Class_Name__c = emailMatcher.group(6).trim();       
            em.Method_Name__c = emailMatcher.group(7).trim();
            insert em;
        }      
        /*
        system.debug('BODY===>' + email.plainTextBody);
        system.debug('ERROR CONTEXT RECORDED===> ' + emErrorContext);
        system.debug('PATTERN: ' + emailPattern.pattern());
        system.debug('Account ID ======>' + emailMatcher.group(1).trim());
        system.debug('Package Name ====>' + emailMatcher.group(5).trim());            
        system.debug('ExceptionType =====> ' + emailMatcher.group(3).trim());
        system.debug('Short Message=====>' + emailMatcher.group(4).trim());
        system.debug('Class Name=====>' + emailMatcher.group(6).trim());
        system.debug('MethodName=====>' + emailMatcher.group(7).trim());
        */
        return result;
    }//close handler method
      
    static testMethod void NPSPErrorProcessorTEST(){
        
        // Create a new email and envelope object
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
              
        //Create a dummy account 
        string idstring = '00D123456789987';
        Account a = new Account(Name = 'TestAccount', Organization_ID__c = idstring); 
        insert a;
       
        //Create new LMA package instance so we can check namespace matching
        sfLma__Package__c p = new sfLma__Package__c(Namespace__c = 'test1', Name = 'TestPackage');
        insert p;
        
        //Create a new Version
        sfLma__Package_Version__c v = new sfLma__Package_Version__c(Name = 'VersionTest', sfLma__Package__c = p.id);
        insert v;
        
        //Create a new License
        sfLma__License__c l = new sfLma__License__c(sfLma__Seats__c = 1, sfLma__Status__c = 'Active', sfLma__Subscriber_Org_ID__c = idstring, sfLma__Package_Version__c = v.id);
        insert l;
                
        //Create a dummy error message using the test org and package         
        email.plainTextBody =   'Apex script unhandled exception by user/organization: 005400000017nGe/' + idstring + '\n' +
                                'Scheduled job Nightly Opportunity Rollup threw unhandled exception.' +
                                'apex script unhandled trigger exception ' + 'visualforce ' + 'custom_validation\n' + 
                                'caused by: System.TestException: Attempted to schedule too many concurrent batch jobs in this org (limit is 5).\n' +
                                'Class.test1.OpportunityRollups.rollupAllContacts: line 839, column 23\n' +
                                'Class.test1.OpportunityRollups.rollupAll: line 794, column 3\n' + 
                                'Class.test1.SCHED_OppRollup.execute: line 5, column 9\n' +
                                'External entry point';
        email.fromAddress ='test@test.com';                
        email.subject = 'Fwd: Developer script exception from TestAccount: Nightly Opportunity Rollup : Attempted to schedule too many concurrent batch jobs in this org (limit is 5).';
        
        NPSPErrorProcessor npspep = new NPSPErrorProcessor();    	
    	
        Test.startTest();
        Messaging.InboundEmailResult result = npspep.handleInboundEmail(email, env);
        Test.stopTest();

        Error_Message__c em = [select e.Short_Message__c, e.Package_Version__c, e.Class_Name__c, e.Method_Name__c, e.Package__c, e.Org_Name__c, e.Message__c, e.Exception_Type__c, e.Error_Context__c, e.Account__c From Error_Message__c e where e.Exception_Type__c = 'TestException'];
        system.assertEquals(em.Package__c, p.id);
        system.assertEquals(em.Exception_Type__c, 'TestException');
        system.assertEquals(em.Account__c, a.id);        
        system.assert(em.Error_Context__c.contains('Batch Apex'));
        system.assert(em.Error_Context__c.contains('Apex Class'));
        system.assert(em.Error_Context__c.contains('Visualforce'));
        system.assert(em.Error_Context__c.contains('Validation Error'));
        system.assertEquals(em.Class_Name__c, 'OpportunityRollups');
        system.assertEquals(em.Method_Name__c, 'rollupAllContacts');
        system.assertEquals(em.Package_Version__c, v.id);
    }
}//Close class