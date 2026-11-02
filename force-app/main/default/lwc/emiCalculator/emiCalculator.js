import { LightningElement, track } from 'lwc';

export default class EmiCalculator extends LightningElement {
    @track propertyPrice = 6500000;
    @track downPaymentPct = 20;
    @track tenureYears = 20;
    @track interestRate = 8.5;

    get downPaymentAmount() {
        return this.propertyPrice * (this.downPaymentPct / 100);
    }

    get principalLoan() {
        return this.propertyPrice - this.downPaymentAmount;
    }

    get totalMonths() {
        return this.tenureYears * 12;
    }

    get emi() {
        const p = this.principalLoan;
        const r = (this.interestRate / 12) / 100;
        const n = this.totalMonths;
        if (n <= 0 || r <= 0) return 0;
        return (p * r * Math.pow(1 + r, n)) / (Math.pow(1 + r, n) - 1);
    }

    get totalPayment() {
        return this.emi * this.totalMonths;
    }

    get totalInterest() {
        return this.totalPayment - this.principalLoan;
    }

    // Formatted Values
    get formattedPrice() {
        return Math.round(this.propertyPrice).toLocaleString('en-IN');
    }

    get formattedDownPayment() {
        return Math.round(this.downPaymentAmount).toLocaleString('en-IN');
    }

    get formattedPrincipal() {
        return Math.round(this.principalLoan).toLocaleString('en-IN');
    }

    get formattedEMI() {
        return Math.round(this.emi).toLocaleString('en-IN');
    }

    get formattedTotalInterest() {
        return Math.round(this.totalInterest).toLocaleString('en-IN');
    }

    get formattedTotalPayment() {
        return Math.round(this.totalPayment).toLocaleString('en-IN');
    }

    handlePriceChange(event) {
        this.propertyPrice = parseFloat(event.target.value);
    }

    handleDownPaymentChange(event) {
        this.downPaymentPct = parseFloat(event.target.value);
    }

    handleTenureChange(event) {
        this.tenureYears = parseFloat(event.target.value);
    }

    handleInterestChange(event) {
        this.interestRate = parseFloat(event.target.value);
    }
}
