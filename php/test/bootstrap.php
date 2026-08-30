<?php

// PHPUnit bootstrap: the binding has no composer autoloader (it's a thin
// hand-written ext-ffi wrapper), so pull the two source files in directly.
declare(strict_types=1);

require __DIR__ . '/../src/Native.php';
require __DIR__ . '/../src/WebDriver.php';
