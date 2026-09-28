defmodule BldgServer.ResidentsAuth do
  @moduledoc """
  The ResidentsAuth context.
  """

  import Ecto.Query, warn: false
  alias BldgServer.Repo

  alias BldgServer.ResidentsAuth.Session

  def pending_verification, do: "PENDING-VERIFICATION"
  def verified, do: "VERIFIED"
  def replaced, do: "REPLACED"

  @doc """
  Returns the list of sessions.

  ## Examples

      iex> list_sessions()
      [%Session{}, ...]

  """
  def list_sessions do
    Repo.all(Session)
  end

  @doc """
  Gets a single session.

  Raises `Ecto.NoResultsError` if the Session does not exist.

  ## Examples

      iex> get_session!(123)
      %Session{}

      iex> get_session!(456)
      ** (Ecto.NoResultsError)

  """
  def get_session!(id) do
    Repo.get!(Session, id)
  end


  def get_session_by_session_id!(session_id) do
    Repo.get_by!(Session, session_id: session_id)
  end

  def get_session_by_session_id(session_id) do
    Repo.get_by(Session, session_id: session_id)
  end

  def get_most_recent_verified_session(resident_id, ip_address) do
    verified_status = verified()
    # lookup a session with verified status & the given resident_id & ip_address
    # TODO add migration to create the corresponding index in the DB
    # Schemaless query: without the explicit type, session_id comes back as the
    # raw 16-byte binary, which then gets baked into the bearer token and makes
    # every later request carrying it fail the session lookup.
    query = from s in "sessions",
      where: s.resident_id == ^resident_id and s.ip_address == ^ip_address and s.status == ^verified_status,
      select: {type(s.session_id, Ecto.UUID), s.updated_at}
    Repo.all(last(query, :updated_at))
  end

  @doc """
  Creates a session.

  ## Examples

      iex> create_session(%{field: value})
      {:ok, %Session{}}

      iex> create_session(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_session(attrs \\ %{}) do
    %Session{}
    |> Session.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a session.

  ## Examples

      iex> update_session(session, %{field: new_value})
      {:ok, %Session{}}

      iex> update_session(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_session(%Session{} = session, attrs) do
    session
    |> Session.changeset(attrs)
    |> Repo.update()
  end

  # mark the active session for a resident as replaced
  def mark_old_session_as_replaced(old_session_id) do
    case get_session_by_session_id(old_session_id) do
      nil -> {:error, "Old session not found"}
      old_session -> update_session(old_session, %{status: replaced()})
    end
  end


  def mark_as_verified(%Session{} = session) do
    update_session(session, %{status: verified(), last_activity_time: DateTime.utc_now()})
  end

  @doc """
  Deletes a session.

  ## Examples

      iex> delete_session(session)
      {:ok, %Session{}}

      iex> delete_session(session)
      {:error, %Ecto.Changeset{}}

  """
  def delete_session(%Session{} = session) do
    Repo.delete(session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking session changes.

  ## Examples

      iex> change_session(session)
      %Ecto.Changeset{data: %Session{}}

  """
  def change_session(%Session{} = session, attrs \\ %{}) do
    Session.changeset(session, attrs)
  end
end
