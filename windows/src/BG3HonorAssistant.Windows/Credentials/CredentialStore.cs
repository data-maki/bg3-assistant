using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace BG3HonorAssistant.Windows.Credentials;

public sealed class CredentialStore
{
    public const string OpenRouterTarget = "BG3HonorAssistant/OpenRouter";
    private const uint CredentialTypeGeneric = 1;
    private const uint CredentialPersistLocalMachine = 2;
    private const int ErrorNotFound = 1168;
    private readonly string target;

    public CredentialStore(string target = OpenRouterTarget)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(target);
        this.target = target;
    }

    public void Save(string secret)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(secret);
        var normalized = secret.Trim();
        var secretBytes = Encoding.UTF8.GetBytes(normalized);
        var targetPointer = Marshal.StringToCoTaskMemUni(target);
        var userPointer = Marshal.StringToCoTaskMemUni("OpenRouter");
        var secretPointer = Marshal.AllocCoTaskMem(secretBytes.Length);

        try
        {
            Marshal.Copy(secretBytes, 0, secretPointer, secretBytes.Length);
            var credential = new NativeCredential
            {
                Type = CredentialTypeGeneric,
                TargetName = targetPointer,
                CredentialBlobSize = checked((uint)secretBytes.Length),
                CredentialBlob = secretPointer,
                Persist = CredentialPersistLocalMachine,
                UserName = userPointer,
            };

            if (!CredentialNativeMethods.CredWrite(in credential, 0))
            {
                throw new Win32Exception(Marshal.GetLastPInvokeError());
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(secretBytes);
            ZeroAndFree(secretPointer, secretBytes.Length);
            Marshal.FreeCoTaskMem(userPointer);
            Marshal.FreeCoTaskMem(targetPointer);
        }
    }

    public string? Read()
    {
        if (!CredentialNativeMethods.CredRead(
                target,
                CredentialTypeGeneric,
                0,
                out var credentialPointer))
        {
            var error = Marshal.GetLastPInvokeError();
            if (error == ErrorNotFound)
            {
                return null;
            }

            throw new Win32Exception(error);
        }

        try
        {
            var credential = Marshal.PtrToStructure<NativeCredential>(credentialPointer);
            if (credential.CredentialBlob == nint.Zero || credential.CredentialBlobSize == 0)
            {
                return string.Empty;
            }

            var bytes = new byte[checked((int)credential.CredentialBlobSize)];
            try
            {
                Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
                return Encoding.UTF8.GetString(bytes);
            }
            finally
            {
                CryptographicOperations.ZeroMemory(bytes);
            }
        }
        finally
        {
            CredentialNativeMethods.CredFree(credentialPointer);
        }
    }

    public bool Delete()
    {
        if (CredentialNativeMethods.CredDelete(target, CredentialTypeGeneric, 0))
        {
            return true;
        }

        var error = Marshal.GetLastPInvokeError();
        if (error == ErrorNotFound)
        {
            return false;
        }

        throw new Win32Exception(error);
    }

    private static void ZeroAndFree(nint pointer, int length)
    {
        if (pointer == nint.Zero)
        {
            return;
        }

        if (length > 0)
        {
            var zeros = new byte[length];
            Marshal.Copy(zeros, 0, pointer, zeros.Length);
        }

        Marshal.FreeCoTaskMem(pointer);
    }
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeCredential
{
    internal uint Flags;
    internal uint Type;
    internal nint TargetName;
    internal nint Comment;
    internal NativeFileTime LastWritten;
    internal uint CredentialBlobSize;
    internal nint CredentialBlob;
    internal uint Persist;
    internal uint AttributeCount;
    internal nint Attributes;
    internal nint TargetAlias;
    internal nint UserName;
}

[StructLayout(LayoutKind.Sequential)]
internal struct NativeFileTime
{
    internal uint LowDateTime;
    internal uint HighDateTime;
}

internal static partial class CredentialNativeMethods
{
    [LibraryImport(
        "advapi32.dll",
        EntryPoint = "CredWriteW",
        SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool CredWrite(in NativeCredential credential, uint flags);

    [LibraryImport(
        "advapi32.dll",
        EntryPoint = "CredReadW",
        SetLastError = true,
        StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool CredRead(
        string target,
        uint type,
        uint flags,
        out nint credential);

    [LibraryImport(
        "advapi32.dll",
        EntryPoint = "CredDeleteW",
        SetLastError = true,
        StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool CredDelete(string target, uint type, uint flags);

    [LibraryImport("advapi32.dll", EntryPoint = "CredFree")]
    internal static partial void CredFree(nint buffer);
}
