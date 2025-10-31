// Returns a list of all tags as strings from a test kit element
const getTags = (tags, elem) => {
  Array.from(elem.children).forEach((e) => {
    if (e.className === 'tag') {
      tags.push(e.innerText);
    }
    getTags(tags, e);
  });
  return tags;
};

// Returns true if test kit should be shown based on standard filter
const filterTag = (testKit, standard) => {
  if (!standard) return true;
  const tags = getTags([], testKit);
  return tags.includes(standard) || standard === 'All Tags';
};

// Returns true if test kit should be shown based on text filter
const filterText = (testKit, text) => {
  const testKitText = testKit.innerText.toLowerCase();
  return testKitText.includes(text);
};

// Ensure all applied filters take effect
const filterAll = (text, standard) => {
  for (let testKit of document.getElementsByName('test-kit')) {
      const foundText = filterText(testKit, text)
      const foundTag = filterTag(testKit, standard)
      const result = foundText && foundTag

      showElement(result, testKit);
  }
};