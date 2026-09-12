namespace Riff.Core;

public static class QueueEditing
{
    public static void Apply<T>(List<T> queue, QueueUpdate update)
    {
        if (update.Action == "clear") { queue.Clear(); return; }
        if (update.Action is not ("remove" or "move")) throw new ArgumentException("Choose clear, remove, or move.");
        if (update.Index is not int index || index < 0 || index >= queue.Count)
            throw new ArgumentException("This sound is no longer queued. Refresh the queue.");
        if (update.Action == "remove") { queue.RemoveAt(index); return; }
        if (update.Destination is not int destination || destination < 0 || destination >= queue.Count)
            throw new ArgumentException("Choose a position in the queue.");
        var sound = queue[index];
        queue.RemoveAt(index);
        queue.Insert(destination, sound);
    }
}
