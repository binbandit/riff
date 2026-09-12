using Riff.Core;
using Xunit;

namespace Riff.Tests;

public class QueueEditingTests
{
    [Fact]
    public void MovingBothDirectionsAndRemovingPreservesOtherEntries()
    {
        var queue = new List<string> { "first", "second", "third" };
        QueueEditing.Apply(queue, new("move", "pc", 0, 2, 0));
        Assert.Equal(["third", "first", "second"], queue);
        QueueEditing.Apply(queue, new("move", "pc", 0, 0, 2));
        Assert.Equal(["first", "second", "third"], queue);
        QueueEditing.Apply(queue, new("remove", "pc", 0, 1));
        Assert.Equal(["first", "third"], queue);
        QueueEditing.Apply(queue, new("clear", "pc", 0));
        Assert.Empty(queue);
    }

    [Fact]
    public void DuplicateAndAnonymousSoundsCanBeEditedIndividually()
    {
        var queue = new List<string> { "repeat", "", "repeat" };
        QueueEditing.Apply(queue, new("move", "pc", 0, 1, 2));
        Assert.Equal(["repeat", "repeat", ""], queue);
        QueueEditing.Apply(queue, new("remove", "pc", 0, 0));
        Assert.Equal(["repeat", ""], queue);
    }

    [Theory]
    [InlineData("move", 0, 3)]
    [InlineData("move", 0, -1)]
    [InlineData("move", -1, 0)]
    [InlineData("move", 0, null)]
    [InlineData("remove", 3, null)]
    [InlineData("remove", null, null)]
    [InlineData("invalid", 0, 1)]
    public void InvalidEditsLeaveTheQueueIntact(string action, int? index, int? destination)
    {
        var queue = new List<string> { "first", "second", "third" };
        Assert.Throws<ArgumentException>(() => QueueEditing.Apply(queue, new(action, "pc", 0, index, destination)));
        Assert.Equal(["first", "second", "third"], queue);
    }
}
