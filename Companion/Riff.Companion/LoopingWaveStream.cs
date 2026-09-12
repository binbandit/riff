using NAudio.Wave;

namespace Riff.Companion;

// The audio route owns the source. Refill each output buffer across the loop boundary.
public sealed class LoopingWaveStream(WaveStream source) : WaveStream
{
    public override WaveFormat WaveFormat => source.WaveFormat;
    public override long Length => source.Length;
    public override long Position { get => source.Position; set => source.Position = value; }

    public override int Read(byte[] buffer, int offset, int count)
    {
        var total = 0;
        while (total < count)
        {
            var read = source.Read(buffer, offset + total, count - total);
            if (read == 0)
            {
                if (source.Position == 0) break;
                source.Position = 0;
                read = source.Read(buffer, offset + total, count - total);
                if (read == 0) break;
            }
            total += read;
        }
        return total;
    }
}
