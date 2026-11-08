using System;
using System.IO;
using System.IO.Compression;
using Ryujinx.Library;

string temporary = Path.Combine(Path.GetTempPath(), "ryu-melo-security-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(temporary);
try
{
    string destination = Path.Combine(temporary, "mod");
    foreach (string unsafeName in new[] { "../mod-other/escaped", "../escaped", "/absolute", "..\\escaped", "C:/absolute" })
    {
        string zip = Path.Combine(temporary, "bad.zip");
        File.Delete(zip);
        using (var archive = ZipFile.Open(zip, ZipArchiveMode.Create))
        using (var writer = new StreamWriter(archive.CreateEntry(unsafeName).Open())) writer.Write("unsafe");
        bool rejected = false;
        try { ZipNative.ExtractManaged(zip, destination, false); }
        catch (InvalidDataException) { rejected = true; }
        if (!rejected) throw new Exception("Unsafe ZIP entry accepted: " + unsafeName);
    }
    string valid = Path.Combine(temporary, "valid.zip");
    using (var archive = ZipFile.Open(valid, ZipArchiveMode.Create))
    using (var writer = new StreamWriter(archive.CreateEntry("nested/test.txt").Open())) writer.Write("valid");
    ZipNative.ExtractManaged(valid, destination, false);
    if (File.ReadAllText(Path.Combine(destination, "nested/test.txt")) != "valid") throw new Exception("Valid ZIP failed.");
    string linkZip = Path.Combine(temporary, "link.zip");
    using (var archive = ZipFile.Open(linkZip, ZipArchiveMode.Create))
    {
        var link = archive.CreateEntry("link");
        link.ExternalAttributes = unchecked((int)(0xA1FFu << 16));
        using var writer = new StreamWriter(link.Open()); writer.Write("../outside");
    }
    bool linkRejected = false;
    try { ZipNative.ExtractManaged(linkZip, destination, false); }
    catch (InvalidDataException) { linkRejected = true; }
    if (!linkRejected) throw new Exception("ZIP symbolic link accepted.");
    if (!OperatingSystem.IsWindows())
    {
        string linked = Path.Combine(destination, "nested/test.txt");
        File.Delete(linked);
        File.CreateSymbolicLink(linked, Path.Combine(temporary, "outside-missing.txt"));
        bool danglingRejected = false;
        try { ZipNative.ExtractManaged(valid, destination, true); }
        catch (InvalidDataException) { danglingRejected = true; }
        if (!danglingRejected || File.Exists(Path.Combine(temporary, "outside-missing.txt")))
            throw new Exception("Dangling extraction link was followed.");
        File.Delete(linked);
    }
    Console.WriteLine("PASS ZIP sibling-prefix traversal, parent traversal, absolute paths, backslash traversal, symlink rejection and valid extraction.");
}
finally { Directory.Delete(temporary, recursive: true); }
