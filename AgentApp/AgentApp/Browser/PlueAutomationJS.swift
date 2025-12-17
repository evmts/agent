import Foundation

enum PlueAutomationJS {
    static let source = """
(function() {
    'use strict';

    // Avoid re-initialization
    if (window.__plue && window.__plue.initialized) return;

    // Namespace
    window.__plue = window.__plue || {};
    window.__plue.initialized = true;

    // Element reference maps
    const elementRefs = new Map();       // ref -> WeakRef<Element>
    const elementToRef = new WeakMap();  // Element -> ref
    let nextRefId = 1;

    // Constants
    const DEFAULT_TIMEOUT = 5000;
    const STABILITY_CHECK_INTERVAL = 100;

    // ==================== ELEMENT REFERENCES ====================

    function getOrCreateRef(element) {
        if (!element) return null;

        let ref = elementToRef.get(element);
        if (ref) return ref;

        ref = 'e' + (nextRefId++);
        elementRefs.set(ref, new WeakRef(element));
        elementToRef.set(element, ref);
        return ref;
    }

    function resolveRef(ref) {
        const weakRef = elementRefs.get(ref);
        if (!weakRef) return null;

        const element = weakRef.deref();
        if (!element || !document.contains(element)) {
            elementRefs.delete(ref);
            return null;
        }
        return element;
    }

    // ==================== MESSAGING ====================

    function sendResult(commandId, payload) {
        window.webkit.messageHandlers.plue.postMessage({
            type: 'commandResult',
            commandId: commandId,
            payload: payload,
            timestamp: Date.now()
        });
    }

    function sendError(commandId, message) {
        window.webkit.messageHandlers.plue.postMessage({
            type: 'commandError',
            commandId: commandId,
            payload: { error: message },
            timestamp: Date.now()
        });
    }

    function sendNotification(type, payload) {
        window.webkit.messageHandlers.plue.postMessage({
            type: type,
            commandId: null,
            payload: payload,
            timestamp: Date.now()
        });
    }

    // ==================== UTILITIES ====================

    function sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    // ==================== VISIBILITY & ACTIONABILITY ====================

    function isVisible(element) {
        if (!element) return false;

        const style = window.getComputedStyle(element);
        if (style.visibility === 'hidden') return false;
        if (style.display === 'none') return false;
        if (parseFloat(style.opacity) === 0) return false;

        const rect = element.getBoundingClientRect();
        if (rect.width === 0 || rect.height === 0) return false;

        return true;
    }

    function isDisabled(element) {
        if (!element) return true;

        if (element.disabled) return true;
        if (element.hasAttribute('disabled')) return true;
        if (element.getAttribute('aria-disabled') === 'true') return true;

        return false;
    }

    async function isStable(element, interval = STABILITY_CHECK_INTERVAL) {
        const rect1 = element.getBoundingClientRect();
        await sleep(interval);
        const rect2 = element.getBoundingClientRect();

        return Math.abs(rect1.x - rect2.x) < 1 &&
               Math.abs(rect1.y - rect2.y) < 1 &&
               Math.abs(rect1.width - rect2.width) < 1 &&
               Math.abs(rect1.height - rect2.height) < 1;
    }

    function receivesPointerEvents(element) {
        const style = window.getComputedStyle(element);
        if (style.pointerEvents === 'none') return false;

        const rect = element.getBoundingClientRect();
        const centerX = rect.left + rect.width / 2;
        const centerY = rect.top + rect.height / 2;

        // Check if element is at the center point
        const topElement = document.elementFromPoint(centerX, centerY);
        if (!topElement) return false;

        return element.contains(topElement) || topElement.contains(element) || element === topElement;
    }

    async function ensureActionable(ref, options = {}) {
        const element = resolveRef(ref);
        if (!element) {
            throw new Error(`Element not found: ${ref}`);
        }

        const timeout = options.timeout ?? DEFAULT_TIMEOUT;
        const startTime = Date.now();

        const checks = {
            visible: options.visible !== false,
            enabled: options.enabled !== false,
            stable: options.stable !== false,
            receivesEvents: options.receivesEvents !== false
        };

        while (Date.now() - startTime < timeout) {
            const results = {
                visible: isVisible(element),
                enabled: !isDisabled(element),
                stable: await isStable(element),
                receivesEvents: receivesPointerEvents(element)
            };

            const failures = Object.entries(checks)
                .filter(([check, required]) => required && !results[check])
                .map(([check]) => check);

            if (failures.length === 0) {
                return element;
            }

            await sleep(100);
        }

        throw new Error(`Element ${ref} not actionable: timed out`);
    }

    // ==================== ACCESSIBILITY HELPERS ====================

    function getRole(element) {
        // Explicit ARIA role takes precedence
        const ariaRole = element.getAttribute('role');
        if (ariaRole) return ariaRole;

        // Implicit roles based on tag
        const tag = element.tagName.toLowerCase();
        const type = element.getAttribute('type')?.toLowerCase();

        const roleMap = {
            'a': element.hasAttribute('href') ? 'link' : null,
            'article': 'article',
            'aside': 'complementary',
            'button': 'button',
            'dialog': 'dialog',
            'footer': 'contentinfo',
            'form': 'form',
            'h1': 'heading',
            'h2': 'heading',
            'h3': 'heading',
            'h4': 'heading',
            'h5': 'heading',
            'h6': 'heading',
            'header': 'banner',
            'img': 'img',
            'input': getInputRole(type),
            'li': 'listitem',
            'main': 'main',
            'nav': 'navigation',
            'ol': 'list',
            'option': 'option',
            'progress': 'progressbar',
            'section': 'region',
            'select': 'combobox',
            'table': 'table',
            'tbody': 'rowgroup',
            'td': 'cell',
            'textarea': 'textbox',
            'th': 'columnheader',
            'thead': 'rowgroup',
            'tr': 'row',
            'ul': 'list'
        };

        return roleMap[tag] || null;
    }

    function getInputRole(type) {
        const inputRoleMap = {
            'button': 'button',
            'checkbox': 'checkbox',
            'email': 'textbox',
            'image': 'button',
            'number': 'spinbutton',
            'password': 'textbox',
            'radio': 'radio',
            'range': 'slider',
            'reset': 'button',
            'search': 'searchbox',
            'submit': 'button',
            'tel': 'textbox',
            'text': 'textbox',
            'url': 'textbox'
        };
        return inputRoleMap[type] || 'textbox';
    }

    function getAccessibleName(element) {
        // aria-label takes precedence
        const ariaLabel = element.getAttribute('aria-label');
        if (ariaLabel) return ariaLabel;

        // aria-labelledby
        const labelledBy = element.getAttribute('aria-labelledby');
        if (labelledBy) {
            const labels = labelledBy.split(' ')
                .map(id => document.getElementById(id))
                .filter(Boolean)
                .map(el => el.textContent?.trim())
                .join(' ');
            if (labels) return labels;
        }

        // For inputs, check associated label
        if (element.tagName === 'INPUT' || element.tagName === 'TEXTAREA' || element.tagName === 'SELECT') {
            const id = element.id;
            if (id) {
                const label = document.querySelector(`label[for="${id}"]`);
                if (label) return label.textContent?.trim();
            }
            // Check wrapping label
            const parentLabel = element.closest('label');
            if (parentLabel) {
                const clone = parentLabel.cloneNode(true);
                clone.querySelectorAll('input, select, textarea').forEach(el => el.remove());
                return clone.textContent?.trim();
            }
            // Placeholder as fallback
            const placeholder = element.getAttribute('placeholder');
            if (placeholder) return placeholder;
        }

        // For images
        if (element.tagName === 'IMG') {
            return element.getAttribute('alt') || '';
        }

        // For buttons and links, use text content
        const role = getRole(element);
        if (role === 'button' || role === 'link' || role === 'menuitem' || role === 'tab') {
            return element.textContent?.trim().substring(0, 100);
        }

        // For headings
        if (role === 'heading') {
            return element.textContent?.trim().substring(0, 100);
        }

        return null;
    }

    function getValue(element) {
        if ('value' in element) {
            return element.value;
        }
        if (element.getAttribute('aria-valuenow')) {
            return element.getAttribute('aria-valuenow');
        }
        return null;
    }

    function getCheckedState(element) {
        if (element.type === 'checkbox' || element.type === 'radio') {
            return element.checked;
        }
        const ariaChecked = element.getAttribute('aria-checked');
        if (ariaChecked === 'true') return true;
        if (ariaChecked === 'false') return false;
        return null;
    }

    function getExpandedState(element) {
        const ariaExpanded = element.getAttribute('aria-expanded');
        if (ariaExpanded === 'true') return true;
        if (ariaExpanded === 'false') return false;
        return null;
    }

    function getBounds(element) {
        const rect = element.getBoundingClientRect();
        return {
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height
        };
    }

    // ==================== SNAPSHOT ====================

    window.__plue.buildSnapshot = function(commandId, options = {}) {
        try {
            const includeHidden = options.includeHidden ?? false;
            const includeBounds = options.includeBounds ?? true;
            const maxDepth = options.maxDepth ?? 50;

            let elementCount = 0;

            function buildNode(element, depth) {
                if (depth > maxDepth) return null;
                if (!includeHidden && !isVisible(element)) return null;

                const role = getRole(element);
                const name = getAccessibleName(element);

                // Skip purely structural nodes
                if (!role && !name && element.children.length === 1) {
                    return buildNode(element.children[0], depth);
                }

                // Skip nodes with no role, no name, and no children
                if (!role && !name && element.children.length === 0) {
                    return null;
                }

                elementCount++;
                const ref = getOrCreateRef(element);

                const node = {
                    ref: ref,
                    role: role || element.tagName.toLowerCase(),
                    name: name,
                    value: getValue(element),
                    description: element.getAttribute('aria-description'),
                    checked: getCheckedState(element),
                    selected: element.getAttribute('aria-selected') === 'true' ? true : null,
                    expanded: getExpandedState(element),
                    disabled: isDisabled(element),
                    required: element.hasAttribute('required') || element.getAttribute('aria-required') === 'true',
                    invalid: element.getAttribute('aria-invalid') === 'true',
                    focused: document.activeElement === element,
                    modal: element.getAttribute('aria-modal') === 'true' ? true : null,
                    boundingBox: includeBounds ? getBounds(element) : null,
                    children: []
                };

                for (const child of element.children) {
                    const childNode = buildNode(child, depth + 1);
                    if (childNode) {
                        node.children.push(childNode);
                    }
                }

                return node;
            }

            const root = buildNode(document.body, 0) || {
                ref: getOrCreateRef(document.body),
                role: 'document',
                name: document.title,
                children: []
            };

            const snapshot = {
                url: window.location.href,
                title: document.title,
                timestamp: Date.now(),
                root: root,
                elementCount: elementCount
            };

            sendResult(commandId, { success: true, snapshot: snapshot });
        } catch (error) {
            sendError(commandId, error.message);
        }
    };

    // ==================== ACTIONS ====================

    window.__plue.click = async function(commandId, ref, options = {}) {
        try {
            const element = await ensureActionable(ref, options);
            const rect = element.getBoundingClientRect();

            const x = options.position?.x ?? (rect.left + rect.width / 2);
            const y = options.position?.y ?? (rect.top + rect.height / 2);

            // Scroll into view if needed
            element.scrollIntoView({ block: 'center', behavior: 'instant' });
            await sleep(50);

            const eventInit = {
                bubbles: true,
                cancelable: true,
                clientX: x,
                clientY: y,
                button: options.button === 'right' ? 2 : (options.button === 'middle' ? 1 : 0),
                buttons: 1,
                view: window
            };

            element.dispatchEvent(new PointerEvent('pointerdown', eventInit));
            element.dispatchEvent(new MouseEvent('mousedown', eventInit));

            if (options.delay) await sleep(options.delay);

            element.dispatchEvent(new PointerEvent('pointerup', eventInit));
            element.dispatchEvent(new MouseEvent('mouseup', eventInit));
            element.dispatchEvent(new MouseEvent('click', eventInit));

            if (options.clickCount === 2) {
                element.dispatchEvent(new MouseEvent('dblclick', eventInit));
            }

            sendResult(commandId, { success: true, ref: ref, actionPerformed: true });
        } catch (error) {
            sendError(commandId, error.message);
        }
    };

    window.__plue.type = async function(commandId, ref, text, options = {}) {
        try {
            const element = await ensureActionable(ref, options);

            // Focus the element
            element.focus();
            await sleep(50);

            // Clear existing content if requested
            if (options.clear && 'value' in element) {
                element.value = '';
                element.dispatchEvent(new Event('input', { bubbles: true }));
            }

            const delay = options.delay ?? 50;

            for (const char of text) {
                element.dispatchEvent(new KeyboardEvent('keydown', {
                    key: char,
                    code: 'Key' + char.toUpperCase(),
                    bubbles: true,
                    cancelable: true
                }));

                if ('value' in element) {
                    element.value += char;
                }

                element.dispatchEvent(new InputEvent('input', {
                    inputType: 'insertText',
                    data: char,
                    bubbles: true,
                    cancelable: true
                }));

                element.dispatchEvent(new KeyboardEvent('keyup', {
                    key: char,
                    code: 'Key' + char.toUpperCase(),
                    bubbles: true,
                    cancelable: true
                }));

                if (delay > 0) await sleep(delay);
            }

            element.dispatchEvent(new Event('change', { bubbles: true }));

            sendResult(commandId, {
                success: true,
                ref: ref,
                actionPerformed: true,
                newValue: 'value' in element ? element.value : null
            });
        } catch (error) {
            sendError(commandId, error.message);
        }
    };

    window.__plue.press = async function(commandId, ref, key, modifiers = []) {
        try {
            const element = ref ? await ensureActionable(ref, {}) : document.activeElement || document.body;

            const eventInit = {
                key: key,
                code: key,
                bubbles: true,
                cancelable: true,
                altKey: modifiers.includes('Alt'),
                ctrlKey: modifiers.includes('Control'),
                metaKey: modifiers.includes('Meta'),
                shiftKey: modifiers.includes('Shift')
            };

            element.dispatchEvent(new KeyboardEvent('keydown', eventInit));
            element.dispatchEvent(new KeyboardEvent('keypress', eventInit));
            element.dispatchEvent(new KeyboardEvent('keyup', eventInit));

            sendResult(commandId, { success: true, ref: ref, actionPerformed: true });
        } catch (error) {
            sendError(commandId, error.message);
        }
    };

    window.__plue.scroll = async function(commandId, ref, direction, amount, options = {}) {
        try {
            const element = ref ? resolveRef(ref) : document.scrollingElement || document.body;
            if (!element) throw new Error(`Element not found: ${ref}`);

            const scrollOptions = {
                behavior: options.smooth ? 'smooth' : 'instant'
            };

            switch (direction) {
                case 'up':
                    element.scrollBy({ top: -amount, ...scrollOptions });
                    break;
                case 'down':
                    element.scrollBy({ top: amount, ...scrollOptions });
                    break;
                case 'left':
                    element.scrollBy({ left: -amount, ...scrollOptions });
                    break;
                case 'right':
                    element.scrollBy({ left: amount, ...scrollOptions });
                    break;
            }

            await sleep(options.smooth ? 500 : 100);

            sendResult(commandId, {
                success: true,
                scrollTop: element.scrollTop,
                scrollLeft: element.scrollLeft
            });
        } catch (error) {
            sendError(commandId, error.message);
        }
    };

    window.__plue.hover = async function(commandId, ref) {
        try {
            const element = await ensureActionable(ref, { stable: false });
            const rect = element.getBoundingClientRect();

            const eventInit = {
                bubbles: true,
                cancelable: true,
                clientX: rect.left + rect.width / 2,
                clientY: rect.top + rect.height / 2,
                view: window
            };

            element.dispatchEvent(new MouseEvent('mouseenter', eventInit));
            element.dispatchEvent(new MouseEvent('mouseover', eventInit));

            sendResult(commandId, { success: true, ref: ref, actionPerformed: true });
        } catch (error) {
            sendError(commandId, error.message);
        }
    };

    window.__plue.focus = async function(commandId, ref) {
        try {
            const element = await ensureActionable(ref, { stable: false });
            element.focus();

            sendResult(commandId, {
                success: true,
                ref: ref,
                actionPerformed: true,
                focused: document.activeElement === element
            });
        } catch (error) {
            sendError(commandId, error.message);
        }
    };

    window.__plue.selectOption = async function(commandId, ref, values) {
        try {
            const element = await ensureActionable(ref, {});

            if (element.tagName !== 'SELECT') {
                throw new Error('Element is not a select');
            }

            for (const option of element.options) {
                option.selected = values.includes(option.value) || values.includes(option.text);
            }

            element.dispatchEvent(new Event('input', { bubbles: true }));
            element.dispatchEvent(new Event('change', { bubbles: true }));

            sendResult(commandId, {
                success: true,
                ref: ref,
                actionPerformed: true,
                newValue: element.value
            });
        } catch (error) {
            sendError(commandId, error.message);
        }
    };

    // ==================== EXTRACTION ====================

    window.__plue.extractText = function(commandId, ref) {
        try {
            const element = resolveRef(ref);
            if (!element) throw new Error(`Element not found: ${ref}`);

            const text = element.innerText || element.textContent || '';
            sendResult(commandId, { success: true, text: text.trim() });
        } catch (error) {
            sendError(commandId, error.message);
        }
    };

    window.__plue.getHTML = function(commandId, ref, outer = false) {
        try {
            const element = resolveRef(ref);
            if (!element) throw new Error(`Element not found: ${ref}`);

            const html = outer ? element.outerHTML : element.innerHTML;
            sendResult(commandId, { success: true, html: html });
        } catch (error) {
            sendError(commandId, error.message);
        }
    };

    window.__plue.screenshot = function(commandId) {
        // Note: This requires additional support from the Swift side
        // We can't capture screenshots purely from JS
        sendError(commandId, 'Screenshot must be handled by native code');
    };

    // ==================== UTILITY ====================

    window.__plue.waitForSelector = async function(commandId, selector, state, timeout) {
        try {
            const startTime = Date.now();

            while (Date.now() - startTime < timeout) {
                const element = document.querySelector(selector);

                switch (state) {
                    case 'attached':
                        if (element) {
                            sendResult(commandId, { success: true, ref: getOrCreateRef(element) });
                            return;
                        }
                        break;
                    case 'detached':
                        if (!element) {
                            sendResult(commandId, { success: true });
                            return;
                        }
                        break;
                    case 'visible':
                        if (element && isVisible(element)) {
                            sendResult(commandId, { success: true, ref: getOrCreateRef(element) });
                            return;
                        }
                        break;
                    case 'hidden':
                        if (!element || !isVisible(element)) {
                            sendResult(commandId, { success: true });
                            return;
                        }
                        break;
                }

                await sleep(100);
            }

            throw new Error(`Timeout waiting for selector: ${selector}`);
        } catch (error) {
            sendError(commandId, error.message);
        }
    };

    window.__plue.evaluate = async function(commandId, script) {
        try {
            const result = eval(script);
            sendResult(commandId, { success: true, result: result });
        } catch (error) {
            sendError(commandId, error.message);
        }
    };

    // ==================== INITIALIZATION ====================

    // Notify that script is ready
    sendNotification('ready', { timestamp: Date.now() });

    console.log('[PlueAutomation] Initialized');
})();
"""
}
