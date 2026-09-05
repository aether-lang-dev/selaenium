using System;
using System.Collections.Generic;

namespace OpenQA.Selenium.Interactions;

/// <summary>
/// A completed, performable action. Mirrors Selenium 4.x's
/// <c>OpenQA.Selenium.Interactions.IAction</c>: <see cref="Actions.Build"/> returns
/// one, and <see cref="Perform"/> posts it.
/// </summary>
public interface IAction
{
    /// <summary>Perform the built action.</summary>
    void Perform();
}

/// <summary>
/// A fluent builder for low-level input (mouse + keyboard) gestures. Mirrors
/// Selenium 4.x's <c>OpenQA.Selenium.Interactions.Actions</c> fluent surface, but
/// rewired to this binding's seam: <see cref="Perform"/> serializes the built ticks
/// into the W3C "actions" payload and posts it through the driver's raw
/// <c>PerformActions</c> command — the same wire shape mainstream produces.
/// <code>
/// new Actions(driver).MoveToElement(el).Click().Build().Perform();
/// new Actions(driver).KeyDown(Keys.Shift).SendKeys("abc").KeyUp(Keys.Shift).Perform();
/// </code>
/// Two devices are emitted, the pointer <c>"mouse"</c> and the keyboard
/// <c>"keyboard"</c>; ticks are kept in lock-step by padding the idle device with
/// pauses, matching the W3C tick model upstream implements in its ActionBuilder.
/// </summary>
public class Actions : IAction
{
    internal const string ElementKey = "element-6066-11e4-a52e-4f735466cecf";

    private const string PointerId = "mouse";
    private const string KeyboardId = "keyboard";
    private const int LeftButton = 0;
    private const int RightButton = 2;

    private readonly IWebDriver _driver;

    // One list per input device; each entry is a single W3C action item. The two
    // lists are aligned tick-for-tick and padded with pauses at serialization time.
    // A device is only emitted if it carried a real (non-pause) action, so a pure
    // mouse gesture posts just the pointer device (the canonical payload shape).
    private readonly List<Dictionary<string, object?>> _pointer = new();
    private readonly List<Dictionary<string, object?>> _keyboard = new();
    private bool _pointerUsed;
    private bool _keyboardUsed;

    /// <summary>Start a new action chain against <paramref name="driver"/>.</summary>
    public Actions(IWebDriver driver)
    {
        _driver = driver ?? throw new ArgumentNullException(nameof(driver));
    }

    // ---- a tick spans both devices: append to one, pause the other ----------

    private Actions PointerTick(Dictionary<string, object?> item)
    {
        _pointer.Add(item);
        _keyboard.Add(Pause());
        _pointerUsed = true;
        return this;
    }

    private Actions KeyboardTick(Dictionary<string, object?> item)
    {
        _keyboard.Add(item);
        _pointer.Add(Pause());
        _keyboardUsed = true;
        return this;
    }

    private static Dictionary<string, object?> Pause() =>
        new() { ["type"] = "pause", ["duration"] = 0 };

    // ---- pointer gestures ---------------------------------------------------

    /// <summary>Move the pointer to the in-view center of <paramref name="toElement"/>.</summary>
    public Actions MoveToElement(IWebElement toElement)
    {
        if (toElement == null)
        {
            throw new ArgumentException("MoveToElement cannot move to a null element", nameof(toElement));
        }

        return MoveToElement(toElement, 0, 0);
    }

    /// <summary>Move the pointer to an offset from the center of
    /// <paramref name="toElement"/>.</summary>
    public Actions MoveToElement(IWebElement toElement, int offsetX, int offsetY)
    {
        if (toElement == null)
        {
            throw new ArgumentException("MoveToElement cannot move to a null element", nameof(toElement));
        }

        return PointerTick(new Dictionary<string, object?>
        {
            ["type"] = "pointerMove",
            ["duration"] = 100,
            ["origin"] = new Dictionary<string, object?> { [ElementKey] = ElementId(toElement) },
            ["x"] = offsetX,
            ["y"] = offsetY,
        });
    }

    /// <summary>Move the pointer by an offset from its current position.</summary>
    public Actions MoveByOffset(int offsetX, int offsetY) =>
        PointerTick(new Dictionary<string, object?>
        {
            ["type"] = "pointerMove",
            ["duration"] = 100,
            ["origin"] = "pointer",
            ["x"] = offsetX,
            ["y"] = offsetY,
        });

    /// <summary>Press-and-hold the left button at the current pointer location.</summary>
    public Actions ClickAndHold() => PointerDown(LeftButton);

    /// <summary>Move to <paramref name="onElement"/>, then press-and-hold the left button.</summary>
    public Actions ClickAndHold(IWebElement onElement) => MoveToElement(onElement).ClickAndHold();

    /// <summary>Release the left button at the current pointer location.</summary>
    public Actions Release() => PointerUp(LeftButton);

    /// <summary>Move to <paramref name="onElement"/>, then release the left button.</summary>
    public Actions Release(IWebElement onElement) => MoveToElement(onElement).Release();

    /// <summary>Left-click at the current pointer location.</summary>
    public Actions Click() => PointerDown(LeftButton).PointerUp(LeftButton);

    /// <summary>Move to <paramref name="onElement"/>, then left-click.</summary>
    public Actions Click(IWebElement onElement) => MoveToElement(onElement).Click();

    /// <summary>Double-click at the current pointer location.</summary>
    public Actions DoubleClick() =>
        PointerDown(LeftButton).PointerUp(LeftButton).PointerDown(LeftButton).PointerUp(LeftButton);

    /// <summary>Move to <paramref name="onElement"/>, then double-click.</summary>
    public Actions DoubleClick(IWebElement onElement) => MoveToElement(onElement).DoubleClick();

    /// <summary>Right-click at the current pointer location.</summary>
    public Actions ContextClick() => PointerDown(RightButton).PointerUp(RightButton);

    /// <summary>Move to <paramref name="onElement"/>, then right-click.</summary>
    public Actions ContextClick(IWebElement onElement) => MoveToElement(onElement).ContextClick();

    /// <summary>Drag <paramref name="source"/> onto <paramref name="target"/>
    /// (click-and-hold, move, release).</summary>
    public Actions DragAndDrop(IWebElement source, IWebElement target) =>
        ClickAndHold(source).MoveToElement(target).Release(target);

    /// <summary>Drag <paramref name="source"/> by an offset (click-and-hold, move,
    /// release).</summary>
    public Actions DragAndDropToOffset(IWebElement source, int offsetX, int offsetY) =>
        ClickAndHold(source).MoveByOffset(offsetX, offsetY).Release();

    private Actions PointerDown(int button) =>
        PointerTick(new Dictionary<string, object?> { ["type"] = "pointerDown", ["button"] = button });

    private Actions PointerUp(int button) =>
        PointerTick(new Dictionary<string, object?> { ["type"] = "pointerUp", ["button"] = button });

    // ---- keyboard gestures --------------------------------------------------

    /// <summary>Press-and-hold a (usually modifier) key.</summary>
    public Actions KeyDown(string theKey) => KeyDown(null, theKey);

    /// <summary>Click <paramref name="element"/> first, then press-and-hold a key.</summary>
    public Actions KeyDown(IWebElement? element, string theKey)
    {
        if (string.IsNullOrEmpty(theKey))
        {
            throw new ArgumentException("The key value must not be null or empty", nameof(theKey));
        }

        if (element != null)
        {
            Click(element);
        }

        return KeyboardTick(new Dictionary<string, object?> { ["type"] = "keyDown", ["value"] = theKey });
    }

    /// <summary>Release a held key.</summary>
    public Actions KeyUp(string theKey) => KeyUp(null, theKey);

    /// <summary>Click <paramref name="element"/> first, then release a held key.</summary>
    public Actions KeyUp(IWebElement? element, string theKey)
    {
        if (string.IsNullOrEmpty(theKey))
        {
            throw new ArgumentException("The key value must not be null or empty", nameof(theKey));
        }

        if (element != null)
        {
            Click(element);
        }

        return KeyboardTick(new Dictionary<string, object?> { ["type"] = "keyUp", ["value"] = theKey });
    }

    /// <summary>Type <paramref name="keysToSend"/> at the current focus (each
    /// character becomes a keyDown/keyUp pair).</summary>
    public Actions SendKeys(string keysToSend) => SendKeys(null, keysToSend);

    /// <summary>Click <paramref name="element"/> first, then type
    /// <paramref name="keysToSend"/>.</summary>
    public Actions SendKeys(IWebElement? element, string keysToSend)
    {
        if (string.IsNullOrEmpty(keysToSend))
        {
            throw new ArgumentException("The key value must not be null or empty", nameof(keysToSend));
        }

        if (element != null)
        {
            Click(element);
        }

        foreach (char key in keysToSend)
        {
            string value = key.ToString();
            KeyboardTick(new Dictionary<string, object?> { ["type"] = "keyDown", ["value"] = value });
            KeyboardTick(new Dictionary<string, object?> { ["type"] = "keyUp", ["value"] = value });
        }

        return this;
    }

    // ---- build / perform ----------------------------------------------------

    /// <summary>Finish building; returns this instance as an <see cref="IAction"/>.</summary>
    public IAction Build() => this;

    /// <summary>Post the built gesture as the W3C "actions" payload and reset the
    /// builder. The payload shape is exactly what mainstream Selenium emits.</summary>
    public void Perform()
    {
        _driver.PerformActions(ToActionSequenceList());
        _pointer.Clear();
        _keyboard.Clear();
        _pointerUsed = false;
        _keyboardUsed = false;
    }

    /// <summary>The W3C "actions" list this chain would post — one entry per input
    /// device that participated. Exposed for inspection/testing without a browser.</summary>
    public IList<object?> ToActionSequenceList()
    {
        var sequences = new List<object?>();

        if (_pointerUsed)
        {
            sequences.Add(new Dictionary<string, object?>
            {
                ["type"] = "pointer",
                ["id"] = PointerId,
                ["parameters"] = new Dictionary<string, object?> { ["pointerType"] = "mouse" },
                ["actions"] = new List<object?>(_pointer),
            });
        }

        if (_keyboardUsed)
        {
            sequences.Add(new Dictionary<string, object?>
            {
                ["type"] = "key",
                ["id"] = KeyboardId,
                ["actions"] = new List<object?>(_keyboard),
            });
        }

        return sequences;
    }

    private static string ElementId(IWebElement element) => element.Id;
}
