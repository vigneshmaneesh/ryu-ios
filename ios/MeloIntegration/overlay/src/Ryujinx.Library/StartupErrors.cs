using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace Ryujinx.Library;

public static class StartupErrors
{
    private static string _message = "";
    public static void Clear() => Volatile.Write(ref _message, "");
    public static void Set(Exception error) => Volatile.Write(ref _message, error.Message);

    [UnmanagedCallersOnly(EntryPoint = "copy_last_startup_error")]
    public static unsafe int Copy(byte* destination, int capacity)
    {
        if (destination == null || capacity < 1) return 0;
        byte[] bytes = Encoding.UTF8.GetBytes(Volatile.Read(ref _message));
        int count = Math.Min(bytes.Length, capacity - 1);
        bytes.AsSpan(0, count).CopyTo(new Span<byte>(destination, count));
        destination[count] = 0;
        return count;
    }
}
