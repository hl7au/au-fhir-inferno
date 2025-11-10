// Returns a list of all tags as strings from a test kit element
const getTags = (tags, elem) => {
  Array.from(elem.children).forEach((e) => {
    if (e.className === 'tag') {
      tags.push(e.innerText.trim());
    }
    getTags(tags, e);
  });
  return tags;
};

const getMaturityList = (maturity, elem) => {
    Array.from(elem.children).forEach((e) => {
        if (e.className === 'maturity') {
            maturity.push(e.innerText.trim());
        }
        getMaturityList(maturity, e);
    });
    return maturity;
};

// Returns true if test kit should be shown based on standard filter
const filterTag = (testKit, standard) => {
  if (!standard) return true;
  const tags = getTags([], testKit);
  return tags.includes(standard) || standard === 'Select tag';
};

// Returns true if test kit should be shown based on text filter
const filterText = (testKit, text) => {
  const testKitText = testKit.innerText.toLowerCase();
  return testKitText.includes(text);
};

const filterMaturity = (testKit, maturity) => {
    if (!maturity) return true;
    const maturityList = getMaturityList([], testKit);

    return maturityList.includes(maturity) || maturity === 'Select Test Kit Maturity';
};

// Ensure all applied filters take effect
const filterAll = (text, standard, maturity) => {
  for (let testKit of document.getElementsByName('test-kit')) {
      const foundText = filterText(testKit, text)
      const foundTag = filterTag(testKit, standard)
      const foundMaturity = filterMaturity(testKit, maturity)
      const result = foundText && foundTag && foundMaturity

      showElement(result, testKit);
  }
};