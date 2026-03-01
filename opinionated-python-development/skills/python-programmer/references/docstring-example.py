"""Example module demonstrating Sphinx docstring conventions.

This module shows the recommended docstring format for modules,
classes, and functions. Use Sphinx/reST style for new projects;
follow existing conventions in established codebases.
"""

from collections.abc import Callable


class Item:
    """A simple data item with a numeric value.

    :ivar value: The item's numeric value.
    """

    def __init__(self, value: int) -> None:
        """Initialize an Item.

        :param value: The numeric value for this item.
        """
        self.value = value


def process_items(
    items: list[Item],
    filter_func: Callable[[Item], bool] | None = None,
    max_count: int = 100,
) -> list[Item]:
    """Process a list of items with optional filtering.

    Applies an optional filter function and limits results to a
    maximum count. Processing maintains the original order of items.

    :param items: The list of items to process. Must not be empty.
    :param filter_func: Optional function to filter items. If None,
        all items are included.
    :param max_count: Maximum number of items to return.
        :type max_count: int (must be positive)
    :returns: Processed and filtered items, up to max_count.
    :rtype: list[Item]
    :raises ValueError: If items list is empty or max_count is not
        positive.
    :raises TypeError: If filter_func is not callable.

    Example usage::

        items = [Item(1), Item(2), Item(3)]
        result = process_items(items, lambda x: x.value > 1, max_count=10)

    .. note::
        This function does not modify the input list. A new list is
        returned.

    .. warning::
        For very large lists (>10000 items), consider using
        :func:`process_items_streaming` instead for better memory
        efficiency.
    """
    if not items:
        raise ValueError("items must not be empty")
    if max_count <= 0:
        raise ValueError("max_count must be positive")

    if filter_func is not None:
        if not callable(filter_func):
            raise TypeError("filter_func must be callable")
        items = [item for item in items if filter_func(item)]

    return items[:max_count]
