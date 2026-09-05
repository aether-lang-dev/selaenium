// The `until.*` wait conditions, shaped to mainstream selenium-webdriver (npm)
// lib/until.js. Pass one to driver.wait(condition, timeout):
//
//   await driver.wait(until.titleContains('Example'), 5000)
//   const el = await driver.wait(until.elementLocated(By.id('x')), 5000)
//
// Adapted to this binding's async ABI: every driver/element accessor here
// (getTitle/getCurrentUrl/findElements/getText/isDisplayed/…) is a Promise-
// returning method, so the upstream `.then(...)` chains work unchanged. The
// conditions build Condition / WebElementCondition instances from webdriver.js.

'use strict'

const by = require('./by')
const error = require('./error')
const webdriver = require('./webdriver')

const Condition = webdriver.Condition
const WebElementCondition = webdriver.WebElementCondition
const WebElement = webdriver.WebElement

// Wait until it is possible to switch focus to the given frame (index, WebElement,
// or a locator matching a frame element).
function ableToSwitchToFrame(frame) {
  let condition
  if (typeof frame === 'number' || frame instanceof WebElement) {
    condition = (driver) => attemptToSwitchFrames(driver, frame)
  } else {
    condition = function (driver) {
      const locator = frame
      return driver.findElements(locator).then(function (els) {
        if (els.length) {
          return attemptToSwitchFrames(driver, els[0])
        }
      })
    }
  }
  return new Condition('to be able to switch to frame', condition)

  function attemptToSwitchFrames(driver, frame) {
    return driver
      .switchTo()
      .frame(frame)
      .then(
        function () {
          return true
        },
        function (e) {
          if (!(e instanceof error.NoSuchFrameError)) {
            throw e
          }
        },
      )
  }
}

// Wait for an alert to be opened.
function alertIsPresent() {
  return new Condition('for alert to be present', function (driver) {
    return Promise.resolve(driver.switchTo().alert()).catch(function (e) {
      if (
        !(
          e instanceof error.NoSuchAlertError ||
          (e instanceof error.WebDriverError && e.message === `can't convert null to object`)
        )
      ) {
        throw e
      }
    })
  })
}

function titleIs(title) {
  return new Condition('for title to be ' + JSON.stringify(title), function (driver) {
    return driver.getTitle().then(function (t) {
      return t === title
    })
  })
}

function titleContains(substr) {
  return new Condition('for title to contain ' + JSON.stringify(substr), function (driver) {
    return driver.getTitle().then(function (title) {
      return title.indexOf(substr) !== -1
    })
  })
}

function titleMatches(regex) {
  return new Condition('for title to match ' + regex, function (driver) {
    return driver.getTitle().then(function (title) {
      return regex.test(title)
    })
  })
}

function urlIs(url) {
  return new Condition('for URL to be ' + JSON.stringify(url), function (driver) {
    return driver.getCurrentUrl().then(function (u) {
      return u === url
    })
  })
}

function urlContains(substrUrl) {
  return new Condition('for URL to contain ' + JSON.stringify(substrUrl), function (driver) {
    return driver.getCurrentUrl().then(function (url) {
      return url && url.includes(substrUrl)
    })
  })
}

function urlMatches(regex) {
  return new Condition('for URL to match ' + regex, function (driver) {
    return driver.getCurrentUrl().then(function (url) {
      return regex.test(url)
    })
  })
}

function elementLocated(locator) {
  locator = by.checkedLocator(locator)
  const locatorStr = typeof locator === 'function' ? 'by function()' : locator + ''
  return new WebElementCondition('for element to be located ' + locatorStr, function (driver) {
    return driver.findElements(locator).then(function (elements) {
      return elements[0]
    })
  })
}

function elementsLocated(locator) {
  locator = by.checkedLocator(locator)
  const locatorStr = typeof locator === 'function' ? 'by function()' : locator + ''
  return new Condition(
    'for at least one element to be located ' + locatorStr,
    function (driver) {
      return driver.findElements(locator).then(function (elements) {
        return elements.length > 0 ? elements : null
      })
    },
  )
}

function stalenessOf(element) {
  return new Condition('element to become stale', function () {
    return element.getTagName().then(
      function () {
        return false
      },
      function (e) {
        if (e instanceof error.StaleElementReferenceError) {
          return true
        }
        throw e
      },
    )
  })
}

function elementIsVisible(element) {
  return new WebElementCondition('until element is visible', function () {
    return element.isDisplayed().then((v) => (v ? element : null))
  })
}

function elementIsNotVisible(element) {
  return new WebElementCondition('until element is not visible', function () {
    return element.isDisplayed().then((v) => (v ? null : element))
  })
}

function elementIsEnabled(element) {
  return new WebElementCondition('until element is enabled', function () {
    return element.isEnabled().then((v) => (v ? element : null))
  })
}

function elementIsDisabled(element) {
  return new WebElementCondition('until element is disabled', function () {
    return element.isEnabled().then((v) => (v ? null : element))
  })
}

function elementIsSelected(element) {
  return new WebElementCondition('until element is selected', function () {
    return element.isSelected().then((v) => (v ? element : null))
  })
}

function elementIsNotSelected(element) {
  return new WebElementCondition('until element is not selected', function () {
    return element.isSelected().then((v) => (v ? null : element))
  })
}

function elementTextIs(element, text) {
  return new WebElementCondition('until element text is', function () {
    return element.getText().then((t) => (t === text ? element : null))
  })
}

function elementTextContains(element, substr) {
  return new WebElementCondition('until element text contains', function () {
    return element.getText().then((t) => (t.indexOf(substr) != -1 ? element : null))
  })
}

function elementTextMatches(element, regex) {
  return new WebElementCondition('until element text matches', function () {
    return element.getText().then((t) => (regex.test(t) ? element : null))
  })
}

module.exports = {
  ableToSwitchToFrame,
  alertIsPresent,
  elementIsDisabled,
  elementIsEnabled,
  elementIsNotSelected,
  elementIsNotVisible,
  elementIsSelected,
  elementIsVisible,
  elementLocated,
  elementsLocated,
  elementTextContains,
  elementTextIs,
  elementTextMatches,
  stalenessOf,
  titleContains,
  titleIs,
  titleMatches,
  urlContains,
  urlIs,
  urlMatches,
}
