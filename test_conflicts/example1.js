// Example JavaScript file with merge conflicts

function calculateTotal1(items) {
  // Their implementation
  // Their implementation test 1

  let sum = 0;
  for (const item of items) {
    sum += item.price * item.quantity;
  }
  // test 2 comment
  return sum;
}

function calculateTotal2(items) {
  // Their implementation
  let sum = 0;
  for (const item of items) {
    sum += item.price * item.quantity;
  }
  return sum;
}

// Their utility function
function formatCurrency(amount, currency = "$") {
  return currency + amount.toFixed(2);
}
// test 2 comment

// Their export with additional functions
module.exports = {
  calculateTotal1,
  formatCurrency,
  parsePrice: (str) => parseFloat(str.replace(/[^\d.]/g, "")),
  // test 2 comment
};
// Example JavaScript file with merge conflicts
// Adding in test branch 1

function calculateTotal(items) {
  // Their implementation
  // Their implementation test 1
  let sum = 0;
  for (const item of items) {
    sum += item.price * item.quantity;
  }
  return sum;
}

// Their utility function
function formatCurrency(amount, currency = "$") {
  // test 2 comment

  return currency + amount.toFixed(2);
}

// Their export with additional functions
module.exports = {
  calculateTotal2,
  // test 2 comment
  formatCurrency,
  parsePrice: (str) => parseFloat(str.replace(/[^\d.]/g, "")),
};
