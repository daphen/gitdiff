# Example Python file with merge conflicts


class DataProcessor:
    def __init__(self, data):
        self.data = data

    # comment 2 in test branch

    def process(self):
        # Their implementation with list comprehension
        return [item * 2 for item in self.data if item > 0]

    def get_stats(self):
        # Their stats implementation with additional metrics
        data = [x for x in self.data if x is not None]
        count = len(data)
        if not count:
            return {"total": 0, "count": 0, "average": 0, "min": None, "max": None}

        total = sum(data)
        return {
            "total": total,
            "count": count,
            "average": total / count,
            "min": min(data),
            "max": max(data),
        }


# Their helper function with additional parameter
def filter_data(data, min_threshold=0, max_threshold=None):
    result = [x for x in data if x >= min_threshold]
    if max_threshold is not None:
        result = [x for x in result if x <= max_threshold]
    return result


# Example Python file with merge conflicts
# comment 2 in test branch


class DataProcessor:
    def __init__(self, data):
        self.data = data

    def process(self):
        # Their implementation with list comprehension
        return [item * 2 for item in self.data if item > 0]
        # comment 2 in test branch

    def get_stats(self):
        # Their stats implementation with additional metrics
        data = [x for x in self.data if x is not None]
        count = len(data)
        if not count:
            return {"total": 0, "count": 0, "average": 0, "min": None, "max": None}

        total = sum(data)
        return {
            "total": total,
            # comment 2 in test branch
            "count": count,
            "average": total / count,
            "min": min(data),
            "max": max(data),
        }


# comment in test branch


# Their helper function with additional parameter
def filter_data(data, min_threshold=0, max_threshold=None):
    result = [x for x in data if x >= min_threshold]
    # comment 2 in test branch

    if max_threshold is not None:
        result = [x for x in result if x <= max_threshold]

    # comment in test branch

    return result
