using Microsoft.EntityFrameworkCore;

namespace TodoApi;

public class Todo
{
    public int Id { get; set; }
    public string Title { get; set; } = "";
    public bool IsDone { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}

public record TodoInput(string? Title, bool IsDone);

public class AppDb(DbContextOptions<AppDb> options) : DbContext(options)
{
    public DbSet<Todo> Todos => Set<Todo>();
}

public static class DbInit
{
    // POC only: creates the tables on startup.
    // In a real project use EF Core migrations, run as a Kubernetes Job or a pipeline step.
    public static async Task EnsureDatabaseAsync(IServiceProvider services, ILogger logger)
    {
        const int maxAttempts = 15;
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                using var scope = services.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDb>();
                await db.Database.EnsureCreatedAsync();
                logger.LogInformation("Database is ready");
                return;
            }
            catch (Exception ex) when (attempt < maxAttempts)
            {
                // The database container may still be starting. Wait and retry.
                logger.LogWarning("Database not ready (attempt {Attempt}/{Max}): {Message}",
                    attempt, maxAttempts, ex.Message);
                await Task.Delay(TimeSpan.FromSeconds(2));
            }
        }
    }
}
