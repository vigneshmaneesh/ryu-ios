using Ryujinx.HLE.HOS.Services.Account.Acc;
using System;
using System.Linq;
using System.Text;
using System.Text.Json.Nodes;

namespace Ryu.iOS.Runtime;

internal static class ProfileManager
{
    internal static JsonObject Manage(string root, JsonObject request)
    {
        ServiceBootstrap.Initialize(root);
        var accounts = ServiceBootstrap.Accounts;
        string operation = request["operation"]!.GetValue<string>();
        var users = accounts.GetAllUsers().ToArray();
        if (operation != "profiles.list")
        {
            string id = request["id"]?.GetValue<string>();
            if (operation != "profiles.add" && !users.Any(u => u.UserId.ToString() == id)) throw new ArgumentException("Unknown user profile.");
            var userId = id == null ? default : new UserId(id);
            if (operation is "profiles.add" or "profiles.rename")
            {
                string name = request["name"]!.GetValue<string>().Trim();
                if (string.IsNullOrWhiteSpace(name) || Encoding.UTF8.GetByteCount(name) > 32) throw new ArgumentException("A profile name must contain 1–32 UTF-8 bytes.");
                if (operation == "profiles.add")
                {
                    if (users.Length >= 8) throw new ArgumentException("The Switch supports eight user profiles.");
                    accounts.AddUser(name, users.First().Image.ToArray());
                }
                else accounts.SetUserName(userId, name);
            }
            else if (operation == "profiles.select") accounts.OpenUser(userId);
            else if (operation == "profiles.image")
            {
                byte[] image = Convert.FromBase64String(request["image"]!.GetValue<string>());
                if (image.Length is < 4 or > 128 * 1024 || image[0] != 0xff || image[1] != 0xd8) throw new ArgumentException("Use a JPEG avatar up to 128 KiB.");
                accounts.SetUserImage(userId, image);
            }
            else if (operation == "profiles.delete")
            {
                if (userId == AccountManager.DefaultUserId) throw new ArgumentException("Keep the default profile as a recovery account.");
                if (request["confirmed"]?.GetValue<bool>() != true) throw new ArgumentException("Deleting a profile also deletes its saves. Confirmation is required.");
                accounts.DeleteUser(userId);
            }
            else throw new ArgumentException("Unknown profile operation.");
        }
        var result = new JsonArray();
        foreach (var user in accounts.GetAllUsers()) result.Add((JsonNode)new JsonObject { ["id"] = user.UserId.ToString(), ["name"] = user.Name, ["selected"] = accounts.LastOpenedUser.UserId == user.UserId, ["image"] = Convert.ToBase64String(user.Image) });
        return new() { ["profiles"] = result };
    }
}
