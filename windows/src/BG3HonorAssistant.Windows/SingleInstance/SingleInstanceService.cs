using System.ComponentModel;
using System.Runtime.InteropServices;

namespace BG3HonorAssistant.Windows.SingleInstance;

public sealed class SingleInstanceService : IDisposable
{
    private static readonly nint HwndBroadcast = new(0xffff);
    private readonly Mutex mutex;
    private bool disposed;

    public SingleInstanceService(string applicationId = "BG3HonorAssistant")
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(applicationId);
        var normalizedId = new string(applicationId
            .Where(character => char.IsLetterOrDigit(character) || character is '.' or '-')
            .ToArray());
        if (normalizedId.Length == 0)
        {
            throw new ArgumentException(
                "The application identifier must contain a letter or digit.",
                nameof(applicationId));
        }

        mutex = new Mutex(
            initiallyOwned: true,
            $"Local\\{normalizedId}.SingleInstance",
            out var createdNew);
        IsPrimary = createdNew;
        ActivationMessage = SingleInstanceNativeMethods.RegisterWindowMessage(
            $"{normalizedId}.Activate");
        if (ActivationMessage == 0)
        {
            mutex.Dispose();
            throw new Win32Exception(Marshal.GetLastPInvokeError());
        }
    }

    public bool IsPrimary { get; }

    public uint ActivationMessage { get; }

    public bool NotifyExistingInstance()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        return SingleInstanceNativeMethods.PostMessage(
            HwndBroadcast,
            ActivationMessage,
            nint.Zero,
            nint.Zero);
    }

    public void Dispose()
    {
        if (disposed)
        {
            return;
        }

        if (IsPrimary)
        {
            mutex.ReleaseMutex();
        }

        mutex.Dispose();
        disposed = true;
    }
}

internal static partial class SingleInstanceNativeMethods
{
    [LibraryImport(
        "user32.dll",
        EntryPoint = "RegisterWindowMessageW",
        SetLastError = true,
        StringMarshalling = StringMarshalling.Utf16)]
    internal static partial uint RegisterWindowMessage(string message);

    [LibraryImport("user32.dll", EntryPoint = "PostMessageW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool PostMessage(
        nint window,
        uint message,
        nint wordParameter,
        nint longParameter);
}
