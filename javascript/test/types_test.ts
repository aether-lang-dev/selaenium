// Type-only smoke test: proves the .d.ts types a realistic consumer program.
// Compiled with `tsc --noEmit` (no runtime); if the declarations are wrong this
// fails to type-check. Not run as JS.
import {
  Builder, By, until, Key, WebDriver, WebElement, ShadowRoot, Select,
  Actions, Capabilities, error, NoSuchElementError,
  resolveDriver, launchDriver, DriverProcess,
} from '../index'

async function main(): Promise<void> {
  const driver: WebDriver = new Builder().forBrowser('firefox').usingServer('http://x').build()
  await driver.get('https://example.com')
  const title: string = await driver.getTitle()

  const el: WebElement = await driver.findElement(By.css('a'))
  await el.click()
  const txt: string = await el.getText()
  const role: string = await el.getAriaRole()

  const sr: ShadowRoot = await el.getShadowRoot()
  const inner: WebElement = await sr.findElement(By.id('x'))

  const sel = new Select(el)
  await sel.selectByValue('v')

  await driver.actions().move({ origin: el }).click(el).perform()
  await driver.wait(until.titleContains('Example'), 5000)
  await driver.findElement(By.id('t')).sendKeys('hi', Key.ENTER)

  const proc: DriverProcess = launchDriver(resolveDriver('firefox'))
  proc.stop()

  try { await driver.findElement(By.id('nope')) }
  catch (e) { if (e instanceof NoSuchElementError) { const c: number = e.code } }

  await driver.quit()
}
void main
