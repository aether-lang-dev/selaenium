using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.Json;
using OpenQA.Selenium;
using OpenQA.Selenium.Interactions;
using OpenQA.Selenium.Support.UI;
using Xunit;
using Shouldly;

namespace SeleniumCore.Tests
{
    // Convenience-tier unit facts — NO browser, NO engine session. Every collaborator
    // is a hand-written stub implementing this binding's own interfaces, so the tier's
    // logic (Keys code points, the WebDriverWait poll loop, SelectElement's option
    // picking, the Actions W3C payload) is exercised in isolation.

    public class KeysTests
    {
        // The W3C private-use code points (§17.4.2), copied verbatim from upstream.
        [Fact]
        public void CodePointsMatchUpstream()
        {
            Keys.Null.ShouldBe(Cp(0xE000));
            Keys.Cancel.ShouldBe(Cp(0xE001));
            Keys.Help.ShouldBe(Cp(0xE002));
            Keys.Backspace.ShouldBe(Cp(0xE003));
            Keys.Tab.ShouldBe(Cp(0xE004));
            Keys.Clear.ShouldBe(Cp(0xE005));
            Keys.Return.ShouldBe(Cp(0xE006));
            Keys.Enter.ShouldBe(Cp(0xE007));
            Keys.Shift.ShouldBe(Cp(0xE008));
            Keys.Control.ShouldBe(Cp(0xE009));
            Keys.Alt.ShouldBe(Cp(0xE00A));
            Keys.Pause.ShouldBe(Cp(0xE00B));
            Keys.Escape.ShouldBe(Cp(0xE00C));
            Keys.Space.ShouldBe(Cp(0xE00D));
            Keys.PageUp.ShouldBe(Cp(0xE00E));
            Keys.PageDown.ShouldBe(Cp(0xE00F));
            Keys.End.ShouldBe(Cp(0xE010));
            Keys.Home.ShouldBe(Cp(0xE011));
            Keys.Left.ShouldBe(Cp(0xE012));
            Keys.Up.ShouldBe(Cp(0xE013));
            Keys.Right.ShouldBe(Cp(0xE014));
            Keys.Down.ShouldBe(Cp(0xE015));
            Keys.Insert.ShouldBe(Cp(0xE016));
            Keys.Delete.ShouldBe(Cp(0xE017));
            Keys.Semicolon.ShouldBe(Cp(0xE018));
            Keys.Equal.ShouldBe(Cp(0xE019));
            Keys.NumberPad0.ShouldBe(Cp(0xE01A));
            Keys.NumberPad9.ShouldBe(Cp(0xE023));
            Keys.Multiply.ShouldBe(Cp(0xE024));
            Keys.Add.ShouldBe(Cp(0xE025));
            Keys.Separator.ShouldBe(Cp(0xE026));
            Keys.Subtract.ShouldBe(Cp(0xE027));
            Keys.Decimal.ShouldBe(Cp(0xE028));
            Keys.Divide.ShouldBe(Cp(0xE029));
            Keys.F1.ShouldBe(Cp(0xE031));
            Keys.F12.ShouldBe(Cp(0xE03C));
            Keys.Meta.ShouldBe(Cp(0xE03D));
            Keys.Command.ShouldBe(Cp(0xE03D));
            Keys.ZenkakuHankaku.ShouldBe(Cp(0xE040));
        }

        [Fact]
        public void AliasesShareCodePoints()
        {
            Keys.LeftShift.ShouldBe(Keys.Shift);
            Keys.LeftControl.ShouldBe(Keys.Control);
            Keys.LeftAlt.ShouldBe(Keys.Alt);
            Keys.ArrowLeft.ShouldBe(Keys.Left);
            Keys.ArrowUp.ShouldBe(Keys.Up);
            Keys.ArrowRight.ShouldBe(Keys.Right);
            Keys.ArrowDown.ShouldBe(Keys.Down);
            Keys.Command.ShouldBe(Keys.Meta);
        }

        [Fact]
        public void EachKeyIsExactlyOneChar() => Keys.Enter.Length.ShouldBe(1);

        private static string Cp(int code) =>
            Convert.ToString(Convert.ToChar(code), CultureInfo.InvariantCulture)!;
    }

    public class WebDriverWaitTests
    {
        // A clock that advances a fixed step every time it is read, so the poll loop
        // is driven deterministically with no real sleeping.
        private sealed class FakeClock : IClock
        {
            private DateTime _now = new DateTime(2020, 1, 1, 0, 0, 0, DateTimeKind.Utc);
            private readonly TimeSpan _step;

            public FakeClock(TimeSpan step) => _step = step;

            public DateTime Now { get { _now = _now.Add(_step); return _now; } }

            public DateTime LaterBy(TimeSpan delay) => _now.Add(delay);

            public bool IsNowBefore(DateTime otherDateTime) => Now < otherDateTime;
        }

        [Fact]
        public void ReturnsOnceConditionIsTruthy()
        {
            var wait = NewWait(TimeSpan.FromSeconds(10));

            int calls = 0;
            string result = wait.Until(_ =>
            {
                calls++;
                return calls >= 3 ? "ready" : null;
            });

            result.ShouldBe("ready");
            calls.ShouldBe(3);
        }

        [Fact]
        public void ReturnsTrueForBoolCondition()
        {
            var wait = NewWait(TimeSpan.FromSeconds(10));
            bool result = wait.Until(_ => true);
            result.ShouldBeTrue();
        }

        [Fact]
        public void ThrowsTimeoutWhenConditionNeverTrue()
        {
            var wait = NewWait(TimeSpan.FromMilliseconds(5));
            Should.Throw<WebDriverTimeoutException>(() => wait.Until(_ => (string?)null));
        }

        [Fact]
        public void IgnoresNotFoundWhilePollingThenSucceeds()
        {
            var wait = NewWait(TimeSpan.FromSeconds(10));

            int calls = 0;
            string result = wait.Until(_ =>
            {
                calls++;
                if (calls < 2)
                {
                    throw new NoSuchElementException("not yet", 17);
                }

                return "found";
            });

            result.ShouldBe("found");
        }

        [Fact]
        public void NonIgnoredExceptionPropagates()
        {
            var wait = NewWait(TimeSpan.FromSeconds(10));
            Should.Throw<InvalidOperationException>(() =>
                wait.Until<string>(_ => throw new InvalidOperationException("boom")));
        }

        // The clock's step must be smaller than the timeout so the loop gets several
        // attempts before it expires; PollingInterval is set to zero so Thread.Sleep
        // returns immediately.
        private static WebDriverWait NewWait(TimeSpan timeout) =>
            new WebDriverWait(new FakeClock(TimeSpan.FromMilliseconds(1)), new NullDriver(), timeout, TimeSpan.Zero);
    }

    public class SelectElementTests
    {
        [Fact]
        public void RejectsNonSelectElement()
        {
            var div = new StubElement { TagName = "div" };
            Should.Throw<UnexpectedTagNameException>(() => new SelectElement(div));
        }

        [Fact]
        public void SelectByValueClicksTheMatchingOption()
        {
            var foo = new StubElement { TagName = "option", Attributes = { ["value"] = "foo" } };
            var bar = new StubElement { TagName = "option", Attributes = { ["value"] = "bar" } };

            var select = new StubElement
            {
                TagName = "select",
                ByResults =
                {
                    [".//option[@value = \"bar\"]"] = new List<IWebElement> { bar },
                },
            };

            var sel = new SelectElement(select);
            sel.SelectByValue("bar");

            bar.ClickCount.ShouldBe(1);
            foo.ClickCount.ShouldBe(0);
        }

        [Fact]
        public void SelectByTextClicksTheMatchingOption()
        {
            var opt = new StubElement { TagName = "option", Text = "Cheddar" };
            var select = new StubElement
            {
                TagName = "select",
                ByResults =
                {
                    [".//option[normalize-space(.) = \"Cheddar\"]"] = new List<IWebElement> { opt },
                },
            };

            new SelectElement(select).SelectByText("Cheddar");
            opt.ClickCount.ShouldBe(1);
        }

        [Fact]
        public void SelectedOptionReturnsTheSelectedOne()
        {
            var a = new StubElement { TagName = "option", Selected = false };
            var b = new StubElement { TagName = "option", Selected = true };
            var select = new StubElement
            {
                TagName = "select",
                ByResults = { ["tag:option"] = new List<IWebElement> { a, b } },
            };

            new SelectElement(select).SelectedOption.ShouldBe(b);
        }

        [Fact]
        public void SelectByValueMissingThrowsNoSuchElement()
        {
            var select = new StubElement { TagName = "select" };
            Should.Throw<NoSuchElementException>(() => new SelectElement(select).SelectByValue("nope"));
        }
    }

    public class ActionsTests
    {
        [Fact]
        public void ClickBuildsCanonicalPointerPayload()
        {
            var driver = new NullDriver();
            var el = new StubElement { TagName = "button", Id = "E1" };

            var actions = new Actions(driver).MoveToElement(el).Click();
            string json = JsonSerializer.Serialize(actions.ToActionSequenceList());

            using var doc = JsonDocument.Parse(json);
            JsonElement seqs = doc.RootElement;
            seqs.GetArrayLength().ShouldBe(1);

            JsonElement pointer = seqs[0];
            pointer.GetProperty("type").GetString().ShouldBe("pointer");
            pointer.GetProperty("id").GetString().ShouldBe("mouse");
            pointer.GetProperty("parameters").GetProperty("pointerType").GetString().ShouldBe("mouse");

            JsonElement acts = pointer.GetProperty("actions");
            acts.GetArrayLength().ShouldBe(3); // move, down, up

            JsonElement move = acts[0];
            move.GetProperty("type").GetString().ShouldBe("pointerMove");
            move.GetProperty("origin")
                .GetProperty("element-6066-11e4-a52e-4f735466cecf").GetString().ShouldBe("E1");

            acts[1].GetProperty("type").GetString().ShouldBe("pointerDown");
            acts[1].GetProperty("button").GetInt32().ShouldBe(0);
            acts[2].GetProperty("type").GetString().ShouldBe("pointerUp");
            acts[2].GetProperty("button").GetInt32().ShouldBe(0);
        }

        [Fact]
        public void ContextClickUsesRightButton()
        {
            var el = new StubElement { TagName = "div", Id = "E2" };
            var actions = new Actions(new NullDriver()).ContextClick(el);
            string json = JsonSerializer.Serialize(actions.ToActionSequenceList());

            using var doc = JsonDocument.Parse(json);
            JsonElement acts = doc.RootElement[0].GetProperty("actions");
            // move, down(2), up(2)
            acts[1].GetProperty("button").GetInt32().ShouldBe(2);
            acts[2].GetProperty("button").GetInt32().ShouldBe(2);
        }

        [Fact]
        public void SendKeysEmitsAKeyDeviceWithKeyDownUpPairs()
        {
            var actions = new Actions(new NullDriver()).SendKeys("ab");
            string json = JsonSerializer.Serialize(actions.ToActionSequenceList());

            using var doc = JsonDocument.Parse(json);
            JsonElement seqs = doc.RootElement;
            seqs.GetArrayLength().ShouldBe(1);

            JsonElement kb = seqs[0];
            kb.GetProperty("type").GetString().ShouldBe("key");
            kb.GetProperty("id").GetString().ShouldBe("keyboard");

            JsonElement acts = kb.GetProperty("actions");
            acts.GetArrayLength().ShouldBe(4); // a-down, a-up, b-down, b-up
            acts[0].GetProperty("type").GetString().ShouldBe("keyDown");
            acts[0].GetProperty("value").GetString().ShouldBe("a");
            acts[1].GetProperty("type").GetString().ShouldBe("keyUp");
            acts[3].GetProperty("value").GetString().ShouldBe("b");
        }

        [Fact]
        public void MixedGestureAlignsBothDevicesTickForTick()
        {
            // KeyDown(Shift) then a pointer Click(): both devices participate, so
            // each must have equal-length action lists (the W3C tick model).
            var el = new StubElement { TagName = "a", Id = "E3" };
            var actions = new Actions(new NullDriver()).KeyDown(Keys.Shift).Click(el).KeyUp(Keys.Shift);
            string json = JsonSerializer.Serialize(actions.ToActionSequenceList());

            using var doc = JsonDocument.Parse(json);
            JsonElement seqs = doc.RootElement;
            seqs.GetArrayLength().ShouldBe(2);

            int pointerLen = -1, keyLen = -1;
            foreach (JsonElement seq in seqs.EnumerateArray())
            {
                int len = seq.GetProperty("actions").GetArrayLength();
                if (seq.GetProperty("type").GetString() == "pointer") pointerLen = len;
                else keyLen = len;
            }

            pointerLen.ShouldBe(keyLen);
        }

        [Fact]
        public void DragAndDropSequencesHoldMoveRelease()
        {
            var src = new StubElement { TagName = "div", Id = "S" };
            var dst = new StubElement { TagName = "div", Id = "D" };
            var actions = new Actions(new NullDriver()).DragAndDrop(src, dst);
            string json = JsonSerializer.Serialize(actions.ToActionSequenceList());

            using var doc = JsonDocument.Parse(json);
            JsonElement acts = doc.RootElement[0].GetProperty("actions");
            // DragAndDrop = ClickAndHold(S).MoveToElement(D).Release(D); Release(D)
            // itself re-moves to D, so the faithful (upstream-matching) sequence is:
            // move(S), down, move(D), move(D), up.
            acts.GetArrayLength().ShouldBe(5);
            acts[0].GetProperty("type").GetString().ShouldBe("pointerMove");
            acts[0].GetProperty("origin").GetProperty("element-6066-11e4-a52e-4f735466cecf").GetString().ShouldBe("S");
            acts[1].GetProperty("type").GetString().ShouldBe("pointerDown");
            acts[2].GetProperty("type").GetString().ShouldBe("pointerMove");
            acts[2].GetProperty("origin").GetProperty("element-6066-11e4-a52e-4f735466cecf").GetString().ShouldBe("D");
            acts[3].GetProperty("type").GetString().ShouldBe("pointerMove");
            acts[3].GetProperty("origin").GetProperty("element-6066-11e4-a52e-4f735466cecf").GetString().ShouldBe("D");
            acts[4].GetProperty("type").GetString().ShouldBe("pointerUp");
        }
    }

    // ---- stubs (implement this binding's public interfaces, no engine) --------

    internal sealed class StubElement : IWebElement
    {
        public string Id { get; set; } = "elem";
        public string TagName { get; set; } = "";
        public string Text { get; set; } = "";
        public bool Enabled { get; set; } = true;
        public bool Selected { get; set; }
        public bool Displayed { get; set; } = true;
        public Rect Rect { get; set; } = new Rect();
        public System.Drawing.Point Location => new System.Drawing.Point((int)Rect.X, (int)Rect.Y);
        public System.Drawing.Size Size => new System.Drawing.Size((int)Rect.Width, (int)Rect.Height);
        public int ClickCount { get; private set; }

        public Dictionary<string, string?> Attributes { get; } = new();
        // Keyed by the XPath string for By.Xpath, "tag:<name>" for By.TagName.
        public Dictionary<string, List<IWebElement>> ByResults { get; } = new();

        public void Click() => ClickCount++;
        public void Clear() { }
        public void SendKeys(string text) { }
        public void Submit() { }
        public string? GetAttribute(string name) => Attributes.TryGetValue(name, out var v) ? v : null;
        public string? GetDomAttribute(string name) => GetAttribute(name);
        public string? GetDomProperty(string name) => GetAttribute(name);
        public string GetCssValue(string name) => "";
        public ISearchContext GetShadowRoot() => throw new NoSuchShadowRootException("stub: no shadow root");

        public IWebElement FindElement(By by)
        {
            var list = FindElements(by);
            return list.Count > 0 ? list[0] : throw new NoSuchElementException("stub: not found", 17);
        }

        public System.Collections.ObjectModel.ReadOnlyCollection<IWebElement> FindElements(By by)
        {
            string key = by.Strategy == "tag name" ? "tag:" + by.Value : by.Value;
            var list = ByResults.TryGetValue(key, out var l) ? l : new List<IWebElement>();
            return new System.Collections.ObjectModel.ReadOnlyCollection<IWebElement>(list);
        }
    }

    // A driver used only to satisfy the Actions/wait constructor. Its command seam
    // is never reached in these unit facts (Actions is inspected via
    // ToActionSequenceList; the wait drives a pure Func). Every member throws if
    // touched, so a test that accidentally hit the wire would fail loudly.
    internal sealed class NullDriver : IWebDriver
    {
        private static T Nope<T>() => throw new InvalidOperationException("NullDriver: no session");

        public string Url { get => Nope<string>(); set => Nope<int>(); }
        public string CurrentUrl => Nope<string>();
        public string Title => Nope<string>();
        public string PageSource => Nope<string>();
        public System.Collections.ObjectModel.ReadOnlyCollection<string> WindowHandles =>
            Nope<System.Collections.ObjectModel.ReadOnlyCollection<string>>();
        public string CurrentWindowHandle => Nope<string>();
        public string SessionId => Nope<string>();

        public void Get(string url) => Nope<int>();
        public void Back() => Nope<int>();
        public void Forward() => Nope<int>();
        public void Refresh() => Nope<int>();
        public INavigation Navigate() => Nope<INavigation>();
        public ITargetLocator SwitchTo() => Nope<ITargetLocator>();
        public IOptions Manage() => Nope<IOptions>();
        public IWebElement FindElement(By by) => Nope<IWebElement>();
        public System.Collections.ObjectModel.ReadOnlyCollection<IWebElement> FindElements(By by) =>
            Nope<System.Collections.ObjectModel.ReadOnlyCollection<IWebElement>>();
        public void SwitchToWindow(string handle) => Nope<int>();
        public JsonElement? ExecuteScript(string script, params object?[] args) => Nope<JsonElement?>();
        public JsonElement? ExecuteAsyncScript(string script, params object?[] args) => Nope<JsonElement?>();
        public void PerformActions(IList<object?> actions) => Nope<int>();
        public void ClearActions() => Nope<int>();
        public void Close() => Nope<int>();
        public void Quit() { }
        public void Dispose() { }
    }
}
