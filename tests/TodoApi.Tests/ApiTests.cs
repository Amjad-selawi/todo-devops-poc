using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using TodoApi;

namespace TodoApi.Tests;

// These tests run in the pipeline on every push and pull request.
// No connection string is set, so the app uses the in-memory database.
public class ApiTests(WebApplicationFactory<Program> factory)
    : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client = factory.CreateClient();
    //test
    [Fact]
    public async Task Root_returns_app_info()
    {
        var response = await _client.GetAsync("/");

        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadAsStringAsync();
        Assert.Contains("todo-api", body);
    }

    [Theory]
    [InlineData("/health/live")]
    [InlineData("/health/ready")]
    public async Task Health_endpoints_are_healthy(string path)
    {
        var response = await _client.GetAsync(path);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Create_then_get_todo()
    {
        var created = await _client.PostAsJsonAsync("/api/todos", new TodoInput("Learn Docker", false));
        Assert.Equal(HttpStatusCode.Created, created.StatusCode);

        var todo = await created.Content.ReadFromJsonAsync<Todo>();
        Assert.NotNull(todo);

        var fetched = await _client.GetFromJsonAsync<Todo>($"/api/todos/{todo!.Id}");
        Assert.Equal("Learn Docker", fetched!.Title);
    }

    [Fact]
    public async Task Update_todo_marks_it_done()
    {
        var created = await _client.PostAsJsonAsync("/api/todos", new TodoInput("Learn Kubernetes", false));
        var todo = await created.Content.ReadFromJsonAsync<Todo>();

        var updated = await _client.PutAsJsonAsync($"/api/todos/{todo!.Id}", new TodoInput("Learn Kubernetes", true));

        Assert.Equal(HttpStatusCode.OK, updated.StatusCode);
        var result = await updated.Content.ReadFromJsonAsync<Todo>();
        Assert.True(result!.IsDone);
    }

    [Fact]
    public async Task Create_without_title_returns_400()
    {
        var response = await _client.PostAsJsonAsync("/api/todos", new TodoInput("  ", false));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Delete_todo_then_get_returns_404()
    {
        var created = await _client.PostAsJsonAsync("/api/todos", new TodoInput("Build a pipeline", false));
        var todo = await created.Content.ReadFromJsonAsync<Todo>();

        var deleted = await _client.DeleteAsync($"/api/todos/{todo!.Id}");
        Assert.Equal(HttpStatusCode.NoContent, deleted.StatusCode);

        var fetched = await _client.GetAsync($"/api/todos/{todo.Id}");
        Assert.Equal(HttpStatusCode.NotFound, fetched.StatusCode);
    }

    [Fact]
    public async Task Chaos_endpoints_are_off_by_default()
    {
        var response = await _client.GetAsync("/api/stress?seconds=1");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }
}
