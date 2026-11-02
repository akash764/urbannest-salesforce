import { LightningElement, api, track, wire } from 'lwc';
import getProjectBrochure from '@salesforce/apex/EnquiryController.getProjectBrochure';

export default class ProjectBrochure extends LightningElement {
    @api projectId;

    @track brochure;
    @track filteredUnits = [];
    @track activeFilter = 'ALL';
    @track isLoading = true;

    @wire(getProjectBrochure, { projectId: '$projectId' })
    wiredBrochure({ error, data }) {
        this.isLoading = false;
        if (data) {
            this.brochure = data;
            this.formatUnits(data.houseUnits);
        } else if (error) {
            console.error('Error fetching project brochure', error);
        }
    }

    formatUnits(units) {
        if (!units) return;
        const processed = units.map(u => {
            let badgeClass = 'slds-badge ';
            if (u.Status__c === 'Available') {
                badgeClass += 'slds-theme_success';
            } else if (u.Status__c === 'Under Offer') {
                badgeClass += 'slds-theme_warning';
            } else if (u.Status__c === 'Reserved') {
                badgeClass += 'slds-badge_inverse';
            } else if (u.Status__c === 'Sold') {
                badgeClass += 'slds-theme_error';
            } else {
                badgeClass += 'slds-theme_shade';
            }
            return {
                ...u,
                statusBadgeClass: badgeClass
            };
        });

        this.allUnits = processed;
        this.applyFilter();
    }

    applyFilter() {
        if (!this.allUnits) return;
        if (this.activeFilter === 'ALL') {
            this.filteredUnits = this.allUnits;
        } else {
            this.filteredUnits = this.allUnits.filter(u => u.BHK_Type__c === this.activeFilter);
        }
    }

    filterAll() {
        this.activeFilter = 'ALL';
        this.applyFilter();
    }

    filter1BHK() {
        this.activeFilter = '1 BHK';
        this.applyFilter();
    }

    filter2BHK() {
        this.activeFilter = '2 BHK';
        this.applyFilter();
    }

    filter3BHK() {
        this.activeFilter = '3 BHK';
        this.applyFilter();
    }

    get allFilterVariant() {
        return this.activeFilter === 'ALL' ? 'brand' : 'neutral';
    }

    get bhk1FilterVariant() {
        return this.activeFilter === '1 BHK' ? 'brand' : 'neutral';
    }

    get bhk2FilterVariant() {
        return this.activeFilter === '2 BHK' ? 'brand' : 'neutral';
    }

    get bhk3FilterVariant() {
        return this.activeFilter === '3 BHK' ? 'brand' : 'neutral';
    }
}
